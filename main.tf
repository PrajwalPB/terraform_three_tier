#vpc
resource "aws_vpc" "my-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "Demo VPC"
  }
}

#creating a public subnet
resource "aws_subnet" "public-subnet-1" {
  vpc_id                  = aws_vpc.my-vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-southeast-1a"
  map_public_ip_on_launch = true #Whether public IP addresses are assigned on instance launch.

  tags = {
    Name = "Publi_subnet_1"
  }
}

resource "aws_subnet" "public-subnet-2" {
  vpc_id                  = aws_vpc.my-vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-southeast-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "Public_Subnet_2"
  }
}

#creating private subnet
resource "aws_subnet" "private-subnet-1" {
  vpc_id                  = aws_vpc.my-vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "ap-southeast-1a"
  map_public_ip_on_launch = false
  tags = {
    Name = "Private_subnet_1"
  }
}

resource "aws_subnet" "private-subnet-2" {
  vpc_id                  = aws_vpc.my-vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "ap-southeast-1b"
  map_public_ip_on_launch = false
  tags = {
    Name = "Private_Subnet_2"
  }
}

#######  creating a internet gateway ########

resource "aws_internet_gateway" "my-vpc-IGW" {
  vpc_id = aws_vpc.my-vpc.id
  tags = {
    Name = "my-vpc_Internet_gateway"
  }
}

####### creating elastic ip ##########
resource "aws_eip" "elastic_ip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.my-vpc-IGW]
}

######### creating a NAT GATEWAY ############
resource "aws_nat_gateway" "my-vpc-NAT" {
  allocation_id = aws_eip.elastic_ip.id # assigining elastic ip to Nat Gateway
  subnet_id     = aws_subnet.public-subnet-1.id
  depends_on    = [aws_internet_gateway.my-vpc-IGW]

  tags = {
    Name = "Nat_gateway"
  }
}



######### creating a public route table ###########


resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my-vpc-IGW.id
  }
  tags = {
    Name = "Public_Route_table"
  }
}



########## creating a private route table ##########

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.my-vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.my-vpc-NAT.id
  }
  tags = {
    Name = "Private_Route_table"
  }

}


#########public route table asssociation ############
resource "aws_route_table_association" "public_rt_ass" {
  subnet_id      = aws_subnet.public-subnet-1.id
  route_table_id = aws_route_table.public_route_table.id
}

##########private route table asssociation ############
resource "aws_route_table_association" "private_rt_ass" {
  subnet_id      = aws_subnet.private-subnet-1.id
  route_table_id = aws_route_table.private_route_table.id

}



################ A subnet group (collection of subnets) is a minimum requirement before creating an RDS Instance.

resource "aws_db_subnet_group" "dbgroup" {
  name       = "private_db_subnet_group"
  subnet_ids = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]


}


############### Creating a RDS instance ##################


resource "aws_db_instance" "db" {
  engine                 = "mysql"
  identifier             = "mydb"
  engine_version         = "8.0.33"
  instance_class         = "db.t2.micro"
  storage_type           = "gp2"
  username               = "admin"
  password               = "12345678"
  skip_final_snapshot    = true
  allocated_storage      = 20
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.dbgroup.name

  tags = {
    Name = "Myrdsdb"
  }
}

########## creating ec2 instance ie private instance (tomcat) #########
resource "aws_instance" "private-server" {
  ami             = "ami-091a58610910a87a9"
  instance_type   = "t2.micro"
  vpc_security_group_ids = [aws_security_group.private_tomcat_sg.id]
  subnet_id       = aws_subnet.private-subnet-1.id
  key_name = "pbsinga"
  user_data  = <<EOF
#!/bin/bash
sudo yum install java-11-amazon-corretto.x86_64 -y
sudo yum install mariadb105-test.x86_64 -y
wget https://dlcdn.apache.org/tomcat/tomcat-8/v8.5.91/bin/apache-tomcat-8.5.91.zip
sudo unzip apache-tomcat-8.5.91.zip
sudo mv apache-tomcat-8.5.91 /mnt/tomcat
wget https://s3-us-west-2.amazonaws.com/studentapi-cit/student.war
wget https://s3-us-west-2.amazonaws.com/studentapi-cit/mysql-connector.jar
sudo mv student.war /mnt/tomcat/webapps/
sudo mv mysql-connector.jar /mnt/tomcat/lib/
inserted_content='    <Resource name="jdbc/TestDB" auth="Container" type="javax.sql.DataSource"
        maxTotal="500" maxIdle="30" maxWaitMillis="1000"
        username="admin" password="12345678" driverClassName="com.mysql.jdbc.Driver"
        url="jdbc:mysql://${aws_db_instance.db.endpoint}/studentapp"/>'

context_file="/mnt/tomcat/conf/context.xml"
awk -v content="$inserted_content" '/<Context>/ { print; print content; next } 1' "$context_file" > temp_file && mv temp_file "$context_file"  
mysql -h ${aws_db_instance.db.address} -u admin -p12345678 -e "CREATE DATABASE studentapp;"
mysql -h ${aws_db_instance.db.address} -u admin -p12345678 -D studentapp -e "CREATE TABLE if not exists students(student_id INT NOT NULL AUTO_INCREMENT,student_name VARCHAR(100) NOT NULL,student_addr VARCHAR(100) NOT NULL,student_age VARCHAR(3) NOT NULL,student_qual VARCHAR(20) NOT NULL,student_percent VARCHAR(10) NOT NULL,student_year_passed VARCHAR(10) NOT NULL,PRIMARY KEY (student_id));"  
sudo chmod 0755 /mnt/tomcat/bin/*
cd /mnt/tomcat/
sudo ./bin/catalina.sh start
EOF
  depends_on = [aws_db_instance.db]
  associate_public_ip_address = false
  tags = {
    Name = "Private_server"
  }
}


############ creating a jump server using nginx as reverse proxy ############
resource "aws_instance" "publuic_instance" {
  ami             = "ami-091a58610910a87a9"
  instance_type   = "t2.micro"
  key_name        = "pbsinga"
  vpc_security_group_ids = [aws_security_group.public_nginx_sg.id]
  subnet_id       = aws_subnet.public-subnet-1.id
  user_data    = <<EOF
#!/bin/bash
sudo yum install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx
cat <<'NGINX_EOF' | sudo tee /etc/nginx/conf.d/reverse-proxy.conf
server {
    listen 80;
    server_name tomcat;

    location / {
        proxy_pass http://${aws_instance.private-server.private_ip}:8080;
    }
}
NGINX_EOF

sudo systemctl restart nginx
EOF

  tags = {
    Name = "Public_Server"
  }

}



################## creating security group #####################
resource "aws_security_group" "public_nginx_sg" {
  name        = "public_sg"
  description = "Allow http and ssh inbound traffic"
  vpc_id      = aws_vpc.my-vpc.id

  ingress {
    description = "http from vpc"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh conenction"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}


############################## creating private instancesecurity group#########

resource "aws_security_group" "private_tomcat_sg" {
  name        = "private_tomcat_sg"
  description = "allow traffic from port 80 to 8080 from public instace"
  vpc_id      = aws_vpc.my-vpc.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
    
  }
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
    
  }
  # Egress rules (outbound)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # Allow all outbound traffic
    cidr_blocks = ["0.0.0.0/0"]  # Update with the appropriate CIDR block for outbound traffic
  }

}

#######################  creating security group for database ##################
resource "aws_security_group" "rds_sg" {
  name   = "rds_sg"
  vpc_id = aws_vpc.my-vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    cidr_blocks = ["10.0.3.0/24"]
  }

}


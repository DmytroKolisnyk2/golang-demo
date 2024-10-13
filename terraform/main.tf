provider "aws" {
  region = "eu-central-1"
}

# Fetch the latest Ubuntu 20.04 LTS AMI dynamically
data "aws_ami" "ubuntu_20_04" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Create VPC
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main_vpc.id
}

# Create Public Subnets for each AZ
resource "aws_subnet" "public_subnets" {
  count      = 3
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = cidrsubnet(aws_vpc.main_vpc.cidr_block, 8, count.index)

  availability_zone = element(["eu-central-1a", "eu-central-1b", "eu-central-1c"], count.index)

  map_public_ip_on_launch = true
}

# Route Table for public subnets
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
}

# Associate subnets with route table
resource "aws_route_table_association" "public_subnets_assoc" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Create a route to the Internet Gateway
resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

# Security group for EC2
resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.main_vpc.id

  # Allow SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance with dynamically fetched Ubuntu 20.04 AMI
resource "aws_instance" "golang_demo" {
  ami                    = data.aws_ami.ubuntu_20_04.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = "1.0.0"

  tags = {
    Name = "GolangDemoInstance"
  }

  user_data = templatefile("ec2-setup.sh", {
    db_endpoint = aws_db_instance.postgres.endpoint,
    db_user     = var.db_username,
    db_password = var.db_password
  })
}

# RDS PostgreSQL instance
resource "aws_db_instance" "postgres" {
  instance_class       = "db.t4g.micro"
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "13"
  db_name              = "golangdb"
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = "default.postgres13"

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name

  skip_final_snapshot = true
}

# RDS Security Group
resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Subnet group for RDS
resource "aws_db_subnet_group" "rds_subnet_group" {
  name        = "rds-subnet-group"
  subnet_ids  = aws_subnet.public_subnets[*].id
  description = "RDS subnet group"
}

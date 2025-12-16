# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Resource to create an SSH key pair in AWS
resource "aws_key_pair" "elk_key" {
  # This uses a local file's public key content
  key_name   = "elk-project-key" 
  public_key = file("~/.ssh/elk-project-key.pub")
}

# Data source to get the latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical owner ID for Ubuntu

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Networking Resources (VPC, Subnet, Internet Gateway) ---

resource "aws_vpc" "elk_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "ELK_VPC"
  }
}

resource "aws_subnet" "elk_subnet" {
  vpc_id            = aws_vpc.elk_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "elk_igw" {
  vpc_id = aws_vpc.elk_vpc.id
}

resource "aws_route_table" "elk_public_rt" {
  vpc_id = aws_vpc.elk_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.elk_igw.id
  }
}

resource "aws_route_table_association" "elk_public_rt_assoc" {
  subnet_id      = aws_subnet.elk_subnet.id
  route_table_id = aws_route_table.elk_public_rt.id
}

# --- Security Groups ---

# Security Group for the ELK Server
resource "aws_security_group" "elk_server_sg" {
  name        = "elk_server_sg"
  description = "Allow inbound traffic for SSH, Kibana, ES, Logstash"
  vpc_id      = aws_vpc.elk_vpc.id

  # SSH access from anywhere (for testing/development, restrict to your IP in production)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kibana UI access from anywhere (restrict to your IP/VPN in production)
  ingress {
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Elasticsearch internal communication (only from internal VPC IPs)
  ingress {
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] 
  }

  # Logstash input from Beats (only from internal VPC IPs)
  ingress {
    from_port   = 5044
    to_port     = 5044
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ELK_Server_SG"
  }
}

# Security Group for Client Instances (monitored servers)
resource "aws_security_group" "client_sg" {
  name        = "client_sg"
  description = "Allow outbound traffic to ELK server and SSH"
  vpc_id      = aws_vpc.elk_vpc.id

  # SSH access from anywhere (for testing/development, restrict to your IP in production)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Allow all outbound traffic (Beats will use this to send data to ELK)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Client_SG"
  }
}


# --- EC2 Instances ---

# ELK Server Instance
resource "aws_instance" "elk_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro" # Using free tier, not recommended for production
  subnet_id     = aws_subnet.elk_subnet.id
  key_name      = aws_key_pair.elk_key.key_name
  vpc_security_group_ids = [aws_security_group.elk_server_sg.id]
  associate_public_ip_address = true

  # Inject the ELK server setup script
  user_data = file("scripts/install_elk.sh")

  tags = {
    Name = "ELK_Server"
  }
}

# Client Instance (Monitored Server)
resource "aws_instance" "elk_client" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro" # Using free tier, not recommended for production
  subnet_id     = aws_subnet.elk_subnet.id
  key_name      = aws_key_pair.elk_key.key_name
  vpc_security_group_ids = [aws_security_group.client_sg.id]
  associate_public_ip_address = true

  # Inject the client setup script.
  user_data = file("scripts/install_filebeats.sh")

  tags = {
    Name = "ELK_Client"
  }
}

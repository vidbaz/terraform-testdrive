provider "aws" {
    region = "us-east-2"
}

variable "budget_email" {}  # Must be defined as TF_VAR_budget_email env variable see README.md for more details
# create a budget alarm to avoid extra charge 
resource "aws_budgets_budget" "total_cost" {
  budget_type  = "COST"
  limit_amount = "1"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
}

variable "vpc_cidr_blocks" {}
variable "subnet_cidr_blocks" {}
variable "availability_zone" {}
variable "env_postfix" {}
variable "personal_ip" {}
variable "instance_type" {}
variable "public_key_location" {}

resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr_blocks
  tags = {
      Name = "vpc-${var.env_postfix}"
      Env = "${var.env_postfix}"
  }
}

resource "aws_subnet" "subnet-1" {
    vpc_id = aws_vpc.vpc.id
    cidr_block = var.subnet_cidr_blocks
    availability_zone = var.availability_zone    # if it is not especified will take a random one
    tags = {
        Name = "subnet-1-${var.env_postfix}"
        Env = var.env_postfix
    }
}

# Give access to Internet whithin the VPC
resource "aws_internet_gateway" "igw-1" {
  vpc_id = aws_vpc.vpc.id
    tags = {
        Name = "igw-1-${var.env_postfix}"
        Env = var.env_postfix
    }
}

resource "aws_default_route_table" "rtb-main" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id
  route {
    cidr_block                = "0.0.0.0/0"
    egress_only_gateway_id    = ""
    gateway_id                = aws_internet_gateway.igw-1.id
    instance_id               = ""
    #ipv6_cidr_block           = ""
    nat_gateway_id            = ""
    network_interface_id      = ""
    transit_gateway_id        = ""
    vpc_peering_connection_id = ""
  }
  tags = {
    Name = "rtb-main_${var.env_postfix}"
    Env = var.env_postfix
  }
}

#Open ports 22 and 8080 with a security group

resource "aws_default_security_group" "default-sg" {
  vpc_id = aws_vpc.vpc.id
  ingress = [{
      from_port = 22
      to_port = 22
      protocol = "tcp"
      cidr_blocks=[var.personal_ip]
      description      = "HTTP"
      ipv6_cidr_blocks = []
      prefix_list_ids = []
      security_groups = []
      self = false
  },
  {
      from_port = 8080
      to_port = 8080
      protocol = "tcp"
      cidr_blocks=["0.0.0.0/0"]
      description      = "HTTP"
      ipv6_cidr_blocks = []
      prefix_list_ids = []
      security_groups = []
      self = false
  }
  ]
  egress = [
    {
      description      = "for all outgoing traffics"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids = []
      security_groups = []
      self = false
    }
  ]
  tags = {
    Name = "sg-1_${var.env_postfix}"
    Env = var.env_postfix
  }
}

# Get information from AWS
data "aws_ami" "linux-image" {
  most_recent = true
  owners = ["amazon"]
  filter {
      name = "name"
      values = ["amzn2-ami-kernel-5*"]
  }
}

output "aws_ami_linux" {
    value = data.aws_ami.linux-image.id
}

# Upload your ssh public key 
resource "aws_key_pair" "dev-key" {
  key_name   = "dev-key"
  public_key = file(var.public_key_location)
}

# Create EC2 Instance
# ssh ec2-user@3.144.21.117
resource "aws_instance" "ec2-server-1" {
  ami = data.aws_ami.linux-image.id
  instance_type = var.instance_type
  subnet_id = aws_subnet.subnet-1.id
  vpc_security_group_ids = [aws_default_security_group.default-sg.id]
  availability_zone = var.availability_zone
  associate_public_ip_address = true
  key_name = aws_key_pair.dev-key.key_name

  user_data = <<EOF
  #!/bin/bash
  sudo yum update -y && sudo yum install -y docker
  sudo systemctl start docker
  sudo usermod -aG docker ec3-user
  docker run -p 8080:80 nginx
  EOF

  tags = {
    Name = "webserver_${var.env_postfix}"
    Env = var.env_postfix
  }
}

output "ec2-server-1-public-ip" {
    value = aws_instance.ec2-server-1.public_ip
}
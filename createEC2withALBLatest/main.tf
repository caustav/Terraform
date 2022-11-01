terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "us-east-2"
}

resource "aws_vpc" "cc_vpc" {
  cidr_block           = var.cc_vpc
#   instance_tenancy     = var.instance_tenancy
  enable_dns_support   = true
  enable_dns_hostnames = true
}

locals {
  ingress_rules = [{
    name        = "HTTPS"
    port        = 443
    description = "Ingress rules for port 443"
    },
    {
      name        = "HTTP"
      port        = 80
      description = "Ingress rules for port 80"
    },
    {
      name        = "SSH"
      port        = 22
      description = "Ingress rules for port 22"
  }]

}

resource "aws_security_group" "sg" {

  name        = "SG4EC2"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.cc_vpc.id
  egress = [
    {
      description      = "for all outgoing traffics"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]

  dynamic "ingress" {
    for_each = local.ingress_rules

    content {
      description = ingress.value.description
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "AWS security group dynamic block"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.cc_vpc.id

  tags = {
    Name = "vpc_igw"
  }
}

resource "aws_subnet" "public_subnet" {
  count              = 2
  vpc_id            = aws_vpc.cc_vpc.id
  cidr_block        = element(cidrsubnets(var.cc_vpc, 8, 4, 4), count.index)
  map_public_ip_on_launch = true
  # availability_zone = "us-east-2a"
  availability_zone = data.aws_availability_zones.azs.names[count.index]

  tags = {
    Name = "public-subnet"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.cc_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public_rt"
  }
}

resource "aws_route_table_association" "public_rt_asso" {
  subnet_id   = element(aws_subnet.public_subnet.*.id, 2)
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_instance" "app_server" {
  ami = "ami-058cc258a01391a67"
  instance_type = "t2.micro"
  count = 2
  subnet_id   = element(aws_subnet.public_subnet.*.id, count.index)
  security_groups = [aws_security_group.sg.id]
  user_data = <<-EOF
    #!/bin/bash
    echo "*** Installing apache2"
    sudo apt update -y
    sudo apt install apache2 -y
    echo "*** Completed Installing apache2"
    EOF
  tags = {
    Name = "test-ec2-with-apache"
  }
}

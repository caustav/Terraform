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
    },
      {
      name        = "TCP"
      port        = 3389
      description = "Ingress rules for port 3389 for RDP"
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
  count              = 1
  vpc_id            = aws_vpc.cc_vpc.id
  cidr_block        = element(cidrsubnets(var.cc_vpc, 8, 4, 4), count.index)
  map_public_ip_on_launch = true
  availability_zone = "us-east-2a"

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
  subnet_id   = element(aws_subnet.public_subnet.*.id, 1)
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_instance" "app_server" {
  ami           = "ami-0321c04d7f279eb63"
  instance_type = "t2.medium"
  key_name = "kcConsole"
  count         = 1
  subnet_id   = element(aws_subnet.public_subnet.*.id, count.index)
  security_groups = [aws_security_group.sg.id]
  tags = {
    Name = "CC-ec2-${count.index}-tf"
  }
  
  associate_public_ip_address = true
}


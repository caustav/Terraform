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
  region = "us-east-2"
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

resource "aws_security_group" "sg_lb" {

  name        = "SG4LB"
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

  ingress {
    from_port        = 0
    to_port          = 65535
    security_groups  = [aws_security_group.sg_lb.id]
    protocol         = "tcp"
  }
}

# create subnets
resource "aws_subnet" "public_subnet" {
  count             = 2
  availability_zone = data.aws_availability_zones.azs.names[count.index]
  cidr_block        = element(cidrsubnets(var.cc_vpc, 8, 4, 4), count.index)
  vpc_id            = aws_vpc.cc_vpc.id
  tags = {
    "Name" = "CC-public-subnet-${count.index}"
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

#create internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.cc_vpc.id

  tags = {
    "Name" = "CC-Internet-Gateway"
  }
}

# create 2 ec2 instances
# resource "aws_instance" "app_server" {
#   ami           = "ami-058cc258a01391a67"
#   instance_type = "t2.micro"
#   count         = 2
#   subnet_id   = element(aws_subnet.public_subnet.*.id, count.index)
#   security_groups = [aws_security_group.sg.id]
#   user_data = <<-EOF
#     #!/bin/bash
#     echo "*** Installing apache2"
#     sudo apt update -y
#     sudo apt install apache2 -y
#     echo "*** Completed Installing apache2"
#     EOF

#   tags = {
#     Name = "CC-ec2-${count.index}-tf"
#   }

#   associate_public_ip_address = true
  
# }

resource "aws_instance" "app_server" {
  ami           = "ami-0f08504d47a4dff07"
  instance_type = "t2.micro"
  count         = 2
  subnet_id   = element(aws_subnet.public_subnet.*.id, count.index)
  security_groups = [aws_security_group.sg.id]
  tags = {
    Name = "CC-ec2-${count.index}-tf"
  }

  associate_public_ip_address = true
  
}

#create a target group
resource "aws_lb_target_group" "tg" {
  name        = "CC-tg-tf"
  port        = 80
  target_type = "instance"
  protocol    = "HTTP"
  vpc_id      = aws_vpc.cc_vpc.id
}

#create target group attachment
resource "aws_alb_target_group_attachment" "tgattachment" {
  count            = length(aws_instance.app_server.*.id) == 2 ? 2 : 0
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = element(aws_instance.app_server.*.id, count.index)
}

# create application load balancer
resource "aws_lb" "lb" {
  name               = "CC-alb-tf"
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.public_subnet.*.id
  security_groups = [aws_security_group.sg_lb.id]
}

# create load balancer listener
resource "aws_lb_listener" "lb_listener_cc" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# create load balancer listener rule
resource "aws_lb_listener_rule" "listener_rule" {
  listener_arn = aws_lb_listener.lb_listener_cc.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn

  }

  condition {
    path_pattern {
      values = ["/"]
    }
  }
}

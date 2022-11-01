# create security group for application load balancer
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

# create application load balancer
resource "aws_lb" "lb" {
  name               = "CC-alb-tf"
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.public_subnet.*.id
  security_groups = [aws_security_group.sg_lb.id]
}

#create a target group
resource "aws_lb_target_group" "tg" {
  name        = "CC-tg-tf"
  port        = 80
  target_type = "instance"
  protocol    = "HTTP"
  vpc_id      = aws_vpc.cc_vpc.id
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
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb"
  description = "Security group for the internal application load balancer"
  vpc_id      = aws_vpc.main.id
  tags        = local.common_tags
}

resource "aws_lb" "order" {
  name               = substr("${local.name_prefix}-order-alb", 0, 32)
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = values(aws_subnet.private)[*].id

  tags = local.common_tags
}

resource "aws_lb_target_group" "order" {
  name        = substr("${local.name_prefix}-order-tg", 0, 32)
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id
  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    matcher             = "200"
    path                = "/actuator/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "order_http" {
  load_balancer_arn = aws_lb.order.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.order.arn
  }

  tags = local.common_tags
}

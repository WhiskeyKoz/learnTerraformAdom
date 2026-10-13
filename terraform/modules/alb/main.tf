# ---------------------------------------------------------------------------
# ALB module
#
# Internet-facing Application Load Balancer in the public subnets (one per AZ).
# It is the ONLY entry point to the application: tasks have no public IPs and
# their security group only accepts traffic from this ALB.
#
#   Internet --80--> ALB (public subnets) --8080--> ECS tasks (private subnets)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Security group
# Ingress: HTTP 80 from the allowed CIDRs.
# Egress:  added by the ecs module (ALB -> tasks SG on the container port),
#          because it references the tasks SG that module owns. Until then
#          the ALB can send nothing anywhere.
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Public ALB: HTTP in from allowed CIDRs, out to ECS tasks only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = toset(var.ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP from ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# ---------------------------------------------------------------------------
# Load balancer
# ---------------------------------------------------------------------------
resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  # Drop requests with malformed HTTP headers instead of forwarding them
  # (mitigates HTTP request smuggling / header injection).
  drop_invalid_header_fields = true

  enable_deletion_protection = var.enable_deletion_protection

  tags = { Name = "${var.name_prefix}-alb" }
}

# ---------------------------------------------------------------------------
# Target group
# target_type = "ip" is required for Fargate: with awsvpc networking every
# task gets its own ENI/IP, and the ALB routes straight to that IP.
# ---------------------------------------------------------------------------
resource "aws_lb_target_group" "app" {
  name        = "${var.name_prefix}-tg"
  vpc_id      = var.vpc_id
  target_type = "ip"
  protocol    = "HTTP"
  port        = var.container_port

  # Shorter drain = faster deployments; plenty for short HTTP requests.
  deregistration_delay = var.deregistration_delay

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.name_prefix}-tg" }
}

# ---------------------------------------------------------------------------
# Listener
# HTTP only for the demo: HTTPS needs an ACM certificate for a domain you own.
# In production: add a 443 listener with the ACM cert and turn this one into
# a 301 redirect to HTTPS.
# ---------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

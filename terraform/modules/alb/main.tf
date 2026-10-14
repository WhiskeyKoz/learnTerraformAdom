# ---------------------------------------------------------------------------
# ALB module
#
# Application Load Balancer, one per layer:
#   internal = false -> internet-facing, in public subnets (frontend, VPC A)
#   internal = true  -> internal, private IPs only, in private subnets
#                       (backend, VPC B - reached over VPC peering)
# It is the ONLY entry point to its tasks: tasks have no public IPs and
# their security group only accepts traffic from this ALB.
#
#   Internet --80--> ALB (public subnets) --8080--> ECS tasks (private subnets)
# ---------------------------------------------------------------------------

locals {
  # "" keeps the Phase 1 names; "backend" -> <prefix>-backend-alb etc.
  base = var.component == "" ? var.name_prefix : "${var.name_prefix}-${var.component}"
}

# ---------------------------------------------------------------------------
# Security group
# Ingress: HTTP 80 from the allowed CIDRs and/or security groups.
# Egress:  added by the ecs module (ALB -> tasks SG on the container port),
#          because it references the tasks SG that module owns. Until then
#          the ALB can send nothing anywhere.
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name = "${local.base}-alb-sg"
  # Changing a SG description forces replacement - the public text is kept
  # exactly as in Phase 1.
  description = var.internal ? "Internal ALB: HTTP in from allowed sources only, out to ECS tasks only" : "Public ALB: HTTP in from allowed CIDRs, out to ECS tasks only"
  vpc_id      = var.vpc_id

  tags = { Name = "${local.base}-alb-sg" }
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

resource "aws_vpc_security_group_ingress_rule" "alb_http_from_sg" {
  for_each = var.ingress_security_groups

  security_group_id            = aws_security_group.alb.id
  description                  = "HTTP from ${each.key} security group"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# ---------------------------------------------------------------------------
# Load balancer
# ---------------------------------------------------------------------------
resource "aws_lb" "this" {
  name               = "${local.base}-alb"
  load_balancer_type = "application"
  internal           = var.internal
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.alb.id]

  # Drop requests with malformed HTTP headers instead of forwarding them
  # (mitigates HTTP request smuggling / header injection).
  drop_invalid_header_fields = true

  enable_deletion_protection = var.enable_deletion_protection

  tags = { Name = "${local.base}-alb" }
}

# ---------------------------------------------------------------------------
# Target group
# target_type = "ip" is required for Fargate: with awsvpc networking every
# task gets its own ENI/IP, and the ALB routes straight to that IP.
# ---------------------------------------------------------------------------
resource "aws_lb_target_group" "app" {
  name        = "${local.base}-tg"
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

  tags = { Name = "${local.base}-tg" }
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

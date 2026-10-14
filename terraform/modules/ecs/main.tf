# ---------------------------------------------------------------------------
# ECS module
#
# Fargate cluster + task definition + service. Tasks run in the PRIVATE
# subnets with no public IP; the ALB is the only way in, and VPC endpoints
# are the only way out (to ECR, S3 and CloudWatch Logs).
#
# Reusable per layer: `component` names the resources (frontend/backend),
# `environment_variables` passes config like BACKEND_URL, and
# `additional_egress_rules` opens specific extra destinations.
# ---------------------------------------------------------------------------

locals {
  container_name = "app"

  # "" keeps the Phase 1 names; "backend" -> <prefix>-backend-cluster etc.
  base = var.component == "" ? var.name_prefix : "${var.name_prefix}-${var.component}"

  # Defaults first, caller overrides win. A map iterates in key order, so the
  # JSON is stable between plans (no task-definition drift).
  environment = merge({ APP_ENV = var.environment, APP_NAME = local.base }, var.environment_variables)
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = "${local.base}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = { Name = "${local.base}-cluster" }
}

# ---------------------------------------------------------------------------
# Security group for the tasks
#
# Ingress: container port, ONLY from the ALB security group (SG reference,
#          not a CIDR - so nothing else in the VPC can reach the tasks).
# Egress:  HTTPS to the Interface endpoints (ECR API/registry, Logs) and to
#          S3 via its prefix list (ECR image layers). Nothing else - no
#          internet, no other VPC resources.
# DNS (VPC resolver) and the task metadata endpoint (169.254.170.2) are
# link-local and not filtered by security groups.
# ---------------------------------------------------------------------------
resource "aws_security_group" "tasks" {
  name        = "${local.base}-ecs-tasks-sg"
  description = "ECS tasks: in from ALB only, out to VPC endpoints only"
  vpc_id      = var.vpc_id

  tags = { Name = "${local.base}-ecs-tasks-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "App port from the ALB only"
  referenced_security_group_id = var.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

resource "aws_vpc_security_group_egress_rule" "tasks_to_endpoints" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "HTTPS to Interface VPC endpoints (ECR, Logs)"
  referenced_security_group_id = var.vpc_endpoints_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_egress_rule" "tasks_to_s3" {
  security_group_id = aws_security_group.tasks.id
  description       = "HTTPS to S3 via Gateway endpoint (ECR image layers)"
  prefix_list_id    = var.s3_prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# Caller-defined extra destinations (e.g. frontend tasks -> backend internal
# ALB across the VPC peering). Keyed by index - order in the list matters.
resource "aws_vpc_security_group_egress_rule" "tasks_additional" {
  for_each = { for idx, rule in var.additional_egress_rules : tostring(idx) => rule }

  security_group_id            = aws_security_group.tasks.id
  description                  = each.value.description
  cidr_ipv4                    = each.value.cidr_ipv4
  referenced_security_group_id = each.value.referenced_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
}

# The matching egress rule on the ALB's SG lives here because it references
# the tasks SG owned by this module: ALB may only talk to the tasks, on the
# container port.
resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  security_group_id            = var.alb_security_group_id
  description                  = "ALB to ECS tasks on the app port"
  referenced_security_group_id = aws_security_group.tasks.id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

# ---------------------------------------------------------------------------
# Task definition
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "app" {
  family                   = "${local.base}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # required by Fargate: one ENI + private IP per task
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64" # must match the image (built with --platform linux/amd64)
  }

  # NOTE: fields AWS would otherwise fill with defaults (hostPort, empty
  # mountPoints/volumesFrom/systemControls, capabilities.add) are set
  # explicitly. Without them every `plan` sees a diff and replaces the task
  # definition (perpetual drift).
  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = var.container_image
      essential = true

      portMappings = [{
        containerPort = var.container_port
        hostPort      = var.container_port # awsvpc: always equals containerPort
        protocol      = "tcp"
      }]

      mountPoints    = []
      volumesFrom    = []
      systemControls = []

      environment = [for name, value in local.environment : { name = name, value = value }]

      # Container hardening (defense in depth - the image already runs as non-root):
      readonlyRootFilesystem = true # an attacker can't modify binaries/code on disk
      linuxParameters = {
        capabilities = { add = [], drop = ["ALL"] } # app needs no Linux capabilities (port 8080 > 1024)
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs" # stream name: ecs/app/<task-id>
        }
      }
    }
  ])

  tags = { Name = "${local.base}-app" }
}

# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------
resource "aws_ecs_service" "app" {
  name             = "${local.base}-app"
  cluster          = aws_ecs_cluster.this.id
  task_definition  = aws_ecs_task_definition.app.arn
  desired_count    = var.desired_count
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  # Tasks get only private IPs in the private subnets. ECS spreads tasks
  # across the given subnets (AZs) automatically.
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  # Give a new task time to boot before ALB health checks can kill it.
  health_check_grace_period_seconds = var.health_check_grace_period

  # Rolling deployment: start new tasks before stopping old ones (no downtime).
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # If a new deployment never becomes healthy (bad image, crash loop),
  # ECS stops it and rolls back to the last working task definition.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Make `terraform apply` wait until the tasks are running and healthy -
  # apply fails (instead of "succeeding") if the deployment is broken.
  wait_for_steady_state = true

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  tags = { Name = "${local.base}-app" }
}

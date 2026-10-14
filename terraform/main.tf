# ---------------------------------------------------------------------------
# Root module: wires the child modules together.
#   module "network_frontend" - VPC A: public + private subnets, IGW, endpoints
#   module "network_backend"  - VPC B: private subnets only, no IGW, endpoints
#   module "peering"          - VPC A <-> VPC B + routes (private RTs only)
#
# Then the same 4 modules once per layer (+ a log group in this file):
#   frontend (VPC A): ecr_frontend, iam_frontend, alb_frontend (public),   ecs_frontend
#   backend  (VPC B): ecr_backend,  iam_backend,  alb_backend  (internal), ecs_backend
# ---------------------------------------------------------------------------

locals {
  # Single naming convention for every resource: <project>-<env>-<thing>
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

# VPC A - frontend / ingress layer.
module "network_frontend" {
  source = "./modules/network"

  name_prefix          = local.name_prefix
  aws_region           = var.aws_region
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# Renamed from "network" in Phase 2 - same objects, nothing is recreated.
moved {
  from = module.network
  to   = module.network_frontend
}

# VPC B - isolated backend layer: private subnets only, no Internet Gateway,
# no route to the internet. Its VPC endpoints (ECR, S3, Logs) let the
# backend pull images and ship logs anyway.
module "network_backend" {
  source = "./modules/network"

  name_prefix           = "${local.name_prefix}-backend"
  aws_region            = var.aws_region
  vpc_cidr              = var.vpc_b_cidr
  availability_zones    = var.availability_zones
  create_public_subnets = false
  private_subnet_cidrs  = var.vpc_b_private_subnet_cidrs
}

# VPC A <-> VPC B. Routes go into the PRIVATE route tables only: frontend
# tasks can reach VPC B, the public subnets (public ALB) cannot.
module "peering" {
  source = "./modules/peering"

  name_prefix = local.name_prefix

  requester_vpc_id       = module.network_frontend.vpc_id
  requester_vpc_cidr     = module.network_frontend.vpc_cidr
  requester_route_tables = { private = module.network_frontend.private_route_table_id }

  accepter_vpc_id       = module.network_backend.vpc_id
  accepter_vpc_cidr     = module.network_backend.vpc_cidr
  accepter_route_tables = { private = module.network_backend.private_route_table_id }
}

# ===========================================================================
# FRONTEND layer - VPC A (public web page)
#   Browser -> public ALB (public subnets) -> frontend tasks (private subnets)
# ===========================================================================

module "ecr_frontend" {
  source = "./modules/ecr"

  name_prefix     = local.name_prefix
  repository_name = "frontend"
  force_delete    = var.ecr_force_delete
  max_image_count = var.ecr_max_image_count
}

# Log groups live in the root module because two modules depend on each one:
# iam (scopes write permissions to it) and ecs (points the awslogs driver at
# it). Creating them in Terraform - instead of letting ECS auto-create them -
# means a set retention period and no logs:CreateLogGroup permission at runtime.
resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${local.name_prefix}/frontend"
  retention_in_days = var.log_retention_days

  tags = { Name = "${local.name_prefix}-frontend-logs" }
}

module "iam_frontend" {
  source = "./modules/iam"

  name_prefix        = local.name_prefix
  component          = "frontend"
  aws_region         = var.aws_region
  ecr_repository_arn = module.ecr_frontend.repository_arn
  log_group_arn      = aws_cloudwatch_log_group.frontend.arn
}

module "alb_frontend" {
  source = "./modules/alb"

  name_prefix       = local.name_prefix
  component         = "frontend"
  vpc_id            = module.network_frontend.vpc_id
  subnet_ids        = module.network_frontend.public_subnet_ids
  ingress_cidrs     = var.alb_ingress_cidrs
  container_port    = var.container_port
  health_check_path = var.health_check_path
}

module "ecs_frontend" {
  source = "./modules/ecs"

  name_prefix = local.name_prefix
  component   = "frontend"
  aws_region  = var.aws_region
  environment = var.environment

  vpc_id                          = module.network_frontend.vpc_id
  private_subnet_ids              = module.network_frontend.private_subnet_ids
  vpc_endpoints_security_group_id = module.network_frontend.vpc_endpoints_security_group_id
  s3_prefix_list_id               = module.network_frontend.s3_prefix_list_id
  alb_security_group_id           = module.alb_frontend.alb_security_group_id
  target_group_arn                = module.alb_frontend.target_group_arn

  container_image    = "${module.ecr_frontend.repository_url}:${var.frontend_image_tag}"
  container_port     = var.container_port
  task_cpu           = var.task_cpu
  task_memory        = var.task_memory
  execution_role_arn = module.iam_frontend.execution_role_arn
  task_role_arn      = module.iam_frontend.task_role_arn
  log_group_name     = aws_cloudwatch_log_group.frontend.name

  # The frontend finds the backend through the internal ALB's DNS name.
  # The name is public DNS but resolves to PRIVATE IPs in VPC B - reachable
  # only over the peering.
  environment_variables = {
    BACKEND_URL = "http://${module.alb_backend.alb_dns_name}"
  }

  # Gate 1 of 2 (outbound): frontend tasks may call ONLY the backend's
  # internal ALB, on port 80 - not the backend tasks, not anything else in
  # VPC B. SG-to-SG reference across the peering (same region).
  additional_egress_rules = [{
    description                  = "HTTP to the backend internal ALB (VPC B, over peering)"
    port                         = 80
    referenced_security_group_id = module.alb_backend.alb_security_group_id
  }]

  desired_count             = var.desired_count
  enable_container_insights = var.enable_container_insights

  # A rule that references a security group in the OTHER VPC is only
  # accepted once the peering is active - and on destroy it must be deleted
  # before the peering. depends_on enforces both orders.
  depends_on = [module.peering]
}

# ===========================================================================
# BACKEND layer - VPC B (private API, no internet)
#   frontend tasks --peering--> internal ALB (private subnets) -> backend tasks
# ===========================================================================

module "ecr_backend" {
  source = "./modules/ecr"

  name_prefix     = local.name_prefix
  repository_name = "backend"
  force_delete    = var.ecr_force_delete
  max_image_count = var.ecr_max_image_count
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.name_prefix}/backend"
  retention_in_days = var.log_retention_days

  tags = { Name = "${local.name_prefix}-backend-logs" }
}

# Own roles: the backend execution role can pull ONLY the backend image and
# write ONLY the backend log group (and the frontend role only its own).
module "iam_backend" {
  source = "./modules/iam"

  name_prefix        = local.name_prefix
  component          = "backend"
  aws_region         = var.aws_region
  ecr_repository_arn = module.ecr_backend.repository_arn
  log_group_arn      = aws_cloudwatch_log_group.backend.arn
}

# Internal ALB: private IPs only, in VPC B's private subnets.
# Gate 2 of 2 (inbound): it accepts HTTP ONLY from the frontend tasks' SG.
# No CIDR rule - not even 10.10.0.0/16 - so the public ALB and anything else
# in VPC A can't call it, even though the peering route exists.
module "alb_backend" {
  source = "./modules/alb"

  name_prefix       = local.name_prefix
  component         = "backend"
  internal          = true
  vpc_id            = module.network_backend.vpc_id
  subnet_ids        = module.network_backend.private_subnet_ids
  container_port    = var.container_port
  health_check_path = var.health_check_path

  ingress_security_groups = {
    frontend_tasks = module.ecs_frontend.tasks_security_group_id
  }

  # Cross-VPC SG reference needs an active peering (see ecs_frontend).
  depends_on = [module.peering]
}

module "ecs_backend" {
  source = "./modules/ecs"

  name_prefix = local.name_prefix
  component   = "backend"
  aws_region  = var.aws_region
  environment = var.environment

  vpc_id                          = module.network_backend.vpc_id
  private_subnet_ids              = module.network_backend.private_subnet_ids
  vpc_endpoints_security_group_id = module.network_backend.vpc_endpoints_security_group_id
  s3_prefix_list_id               = module.network_backend.s3_prefix_list_id
  alb_security_group_id           = module.alb_backend.alb_security_group_id
  target_group_arn                = module.alb_backend.target_group_arn

  container_image    = "${module.ecr_backend.repository_url}:${var.backend_image_tag}"
  container_port     = var.container_port
  task_cpu           = var.task_cpu
  task_memory        = var.task_memory
  execution_role_arn = module.iam_backend.execution_role_arn
  task_role_arn      = module.iam_backend.task_role_arn
  log_group_name     = aws_cloudwatch_log_group.backend.name

  desired_count             = var.desired_count
  enable_container_insights = var.enable_container_insights
}

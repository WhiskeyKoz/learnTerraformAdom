# ---------------------------------------------------------------------------
# Root module: wires the child modules together.
#   module "network_frontend" - VPC A: public + private subnets, IGW, endpoints
#   module "network_backend"  - VPC B: private subnets only, no IGW, endpoints
#   module "peering"          - VPC A <-> VPC B + routes (private RTs only)
#   module "ecr"              - image repository
#   module "iam"              - task execution role + task role (+ app log group here)
#   module "alb"              - public ALB, target group, listener
#   module "ecs"              - cluster, task definition, service
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

module "ecr" {
  source = "./modules/ecr"

  name_prefix     = local.name_prefix
  force_delete    = var.ecr_force_delete
  max_image_count = var.ecr_max_image_count
}

# Log group for the app containers. Lives in the root module because two
# modules depend on it: iam (scopes write permissions to it) and ecs
# (points the awslogs driver at it). Creating it in Terraform - instead of
# letting ECS auto-create it - means a set retention period and no
# logs:CreateLogGroup permission at runtime.
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name_prefix}/app"
  retention_in_days = var.log_retention_days

  tags = { Name = "${local.name_prefix}-app-logs" }
}

module "iam" {
  source = "./modules/iam"

  name_prefix        = local.name_prefix
  aws_region         = var.aws_region
  ecr_repository_arn = module.ecr.repository_arn
  log_group_arn      = aws_cloudwatch_log_group.app.arn
}

module "alb" {
  source = "./modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.network_frontend.vpc_id
  subnet_ids        = module.network_frontend.public_subnet_ids
  ingress_cidrs     = var.alb_ingress_cidrs
  container_port    = var.container_port
  health_check_path = var.health_check_path
}

module "ecs" {
  source = "./modules/ecs"

  name_prefix = local.name_prefix
  aws_region  = var.aws_region
  environment = var.environment

  vpc_id                          = module.network_frontend.vpc_id
  private_subnet_ids              = module.network_frontend.private_subnet_ids
  vpc_endpoints_security_group_id = module.network_frontend.vpc_endpoints_security_group_id
  s3_prefix_list_id               = module.network_frontend.s3_prefix_list_id
  alb_security_group_id           = module.alb.alb_security_group_id
  target_group_arn                = module.alb.target_group_arn

  container_image    = "${module.ecr.repository_url}:${var.image_tag}"
  container_port     = var.container_port
  task_cpu           = var.task_cpu
  task_memory        = var.task_memory
  execution_role_arn = module.iam.execution_role_arn
  task_role_arn      = module.iam.task_role_arn
  log_group_name     = aws_cloudwatch_log_group.app.name

  desired_count             = var.desired_count
  enable_container_insights = var.enable_container_insights
}

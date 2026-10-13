# ---------------------------------------------------------------------------
# Root module: wires the child modules together.
# Each module is added step by step:
#   1. module "network" - VPC, subnets, IGW, route tables, VPC endpoints
#   2. module "ecr"     - image repository
#   3. module "iam"     - task execution role + task role
#   4. module "alb"     - public ALB, target group, listener
#   5. module "ecs"     - cluster, task definition, service
# ---------------------------------------------------------------------------

locals {
  # Single naming convention for every resource: <project>-<env>-<thing>
  name_prefix = "${var.project_name}-${var.environment}"
}

module "network" {
  source = "./modules/network"

  name_prefix          = local.name_prefix
  aws_region           = var.aws_region
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
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

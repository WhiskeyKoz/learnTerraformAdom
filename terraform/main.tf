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

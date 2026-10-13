# ---------------------------------------------------------------------------
# Phase 1 configuration. Change values here - not in the .tf files.
# This file contains NO secrets and is committed on purpose.
# ---------------------------------------------------------------------------

# General
aws_region   = "eu-central-1"
project_name = "adom-demo"
environment  = "dev"

# Networking
# /16 leaves room for Phase 2 - VPC B must use a NON-overlapping range
# (e.g. 10.20.0.0/16) or VPC peering will be impossible.
vpc_cidr             = "10.10.0.0/16"
availability_zones   = ["eu-central-1a", "eu-central-1b"]
public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24"]
private_subnet_cidrs = ["10.10.11.0/24", "10.10.12.0/24"]

# Application / ECS
container_port    = 8080
image_tag         = "latest"
task_cpu          = 256
task_memory       = 512
desired_count     = 2
health_check_path = "/health"

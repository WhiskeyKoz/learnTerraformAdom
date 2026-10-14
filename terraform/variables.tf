# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
}

variable "project_name" {
  description = "Short project name, used as a prefix for resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "project_name must be 3-20 chars: lowercase letters, digits, hyphens."
  }
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "Exactly two AZs to spread subnets across for high availability."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Phase 1 expects exactly 2 availability zones."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs for the public subnets (ALB). One per AZ, same order as availability_zones."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Provide exactly 2 public subnet CIDRs."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDRs for the private subnets (ECS tasks). One per AZ, same order as availability_zones."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Provide exactly 2 private subnet CIDRs."
  }
}

# ---------------------------------------------------------------------------
# Networking - VPC B (Phase 2 backend: private-only, no internet)
# Uses the same availability_zones as VPC A.
# ---------------------------------------------------------------------------
variable "vpc_b_cidr" {
  description = "CIDR block for VPC B (backend). Must NOT overlap vpc_cidr, or VPC peering is impossible."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_b_cidr, 0))
    error_message = "vpc_b_cidr must be a valid IPv4 CIDR block."
  }
}

variable "vpc_b_private_subnet_cidrs" {
  description = "CIDRs for VPC B's private subnets (backend tasks + internal ALB). One per AZ, same order as availability_zones."
  type        = list(string)

  validation {
    condition     = length(var.vpc_b_private_subnet_cidrs) == 2 && alltrue([for c in var.vpc_b_private_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "Provide exactly 2 valid private subnet CIDRs for VPC B."
  }
}

# ---------------------------------------------------------------------------
# Container registry (ECR)
# ---------------------------------------------------------------------------
variable "ecr_force_delete" {
  description = "Allow destroy to delete the ECR repo even if it contains images (true for dev/demo, false for prod)."
  type        = bool
  default     = false
}

variable "ecr_max_image_count" {
  description = "Number of most recent images ECR keeps; older ones are expired."
  type        = number
  default     = 10
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
variable "log_retention_days" {
  description = "How long CloudWatch keeps container logs."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs supports (e.g. 1, 3, 7, 14, 30, 90, 365)."
  }
}

# ---------------------------------------------------------------------------
# Application / ECS
# ---------------------------------------------------------------------------
variable "container_port" {
  description = "Port the container listens on (must match the Dockerfile)."
  type        = number
  default     = 8080
}

variable "image_tag" {
  description = "Tag of the image in ECR to deploy (e.g. v1.0.0 or a git SHA)."
  type        = string

  # Tags are immutable in ECR, so a moving tag like "latest" would make
  # every push after the first one fail.
  validation {
    condition     = var.image_tag != "latest"
    error_message = "Use a versioned tag (e.g. v1.0.0 or a git SHA), not \"latest\"."
  }
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB. Must be a valid pairing with task_cpu."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of ECS tasks to run. Use >= 2 so both AZs get a task."
  type        = number
  default     = 2
}

variable "health_check_path" {
  description = "Path the ALB uses to health-check the containers."
  type        = string
  default     = "/health"
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights on the ECS cluster (extra cost)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Load balancer
# ---------------------------------------------------------------------------
variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the public ALB on HTTP 80. Restrict to your own IP (x.x.x.x/32) for a private demo."
  type        = list(string)

  validation {
    condition     = alltrue([for c in var.alb_ingress_cidrs : can(cidrhost(c, 0))])
    error_message = "Every entry in alb_ingress_cidrs must be a valid IPv4 CIDR."
  }
}

variable "name_prefix" {
  description = "Prefix for resource names (<project>-<env>)."
  type        = string
}

variable "aws_region" {
  description = "Region, used to build VPC endpoint service names."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "availability_zones" {
  description = "AZs to spread subnets across. Index i pairs with subnet CIDR i."
  type        = list(string)
}

variable "create_public_subnets" {
  description = "Create public subnets + Internet Gateway. false = private-only VPC with no internet path at all (Phase 2 VPC B)."
  type        = bool
  default     = true
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per AZ. Ignored (may be empty) when create_public_subnets = false."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.create_public_subnets || length(var.public_subnet_cidrs) == length(var.availability_zones)
    error_message = "With create_public_subnets = true, provide one public subnet CIDR per availability zone."
  }
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, one per AZ."
  type        = list(string)
}

variable "interface_endpoint_services" {
  description = "AWS services reachable from private subnets via Interface VPC endpoints. Defaults are the minimum Fargate needs to pull from ECR and ship logs."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "logs"]
}

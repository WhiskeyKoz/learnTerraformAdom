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

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per AZ."
  type        = list(string)
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

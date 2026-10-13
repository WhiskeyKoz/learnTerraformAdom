variable "name_prefix" {
  description = "Prefix for resource names (<project>-<env>)."
  type        = string
}

variable "aws_region" {
  description = "Region, used to scope the role trust policy to this region's ECS."
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository the execution role may pull from."
  type        = string
}

variable "log_group_arn" {
  description = "ARN of the CloudWatch log group the containers write to."
  type        = string
}

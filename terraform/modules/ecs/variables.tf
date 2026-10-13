variable "name_prefix" {
  description = "Prefix for resource names (<project>-<env>)."
  type        = string
}

variable "aws_region" {
  description = "Region (used by the awslogs log driver)."
  type        = string
}

variable "environment" {
  description = "Environment name, passed to the app as APP_ENV."
  type        = string
}

# --- Networking --------------------------------------------------------------
variable "vpc_id" {
  description = "VPC for the tasks security group."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets (one per AZ) the tasks run in."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ALB security group - the only allowed source of traffic to the tasks."
  type        = string
}

variable "vpc_endpoints_security_group_id" {
  description = "Security group of the Interface VPC endpoints (ECR, Logs)."
  type        = string
}

variable "s3_prefix_list_id" {
  description = "S3 managed prefix list (Gateway endpoint) - ECR image layers live in S3."
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group the service registers tasks in."
  type        = string
}

# --- Task --------------------------------------------------------------------
variable "container_image" {
  description = "Full image reference: <ecr_repository_url>:<tag>."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
}

variable "task_cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)."
  type        = number
}

variable "task_memory" {
  description = "Task memory in MiB."
  type        = number
}

variable "execution_role_arn" {
  description = "Task execution role (image pull + logs)."
  type        = string
}

variable "task_role_arn" {
  description = "Task role (app runtime identity)."
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group for container logs."
  type        = string
}

# --- Service -----------------------------------------------------------------
variable "desired_count" {
  description = "Number of tasks to keep running."
  type        = number
}

variable "health_check_grace_period" {
  description = "Seconds ECS ignores failing ALB health checks after a task starts."
  type        = number
  default     = 30
}

variable "enable_container_insights" {
  description = "CloudWatch Container Insights metrics for the cluster (extra cost)."
  type        = bool
  default     = false
}

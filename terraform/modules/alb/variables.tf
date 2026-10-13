variable "name_prefix" {
  description = "Prefix for resource names (<project>-<env>)."
  type        = string
}

variable "vpc_id" {
  description = "VPC the ALB and target group belong to."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets (one per AZ) to place the ALB in."
  type        = list(string)
}

variable "ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB on HTTP 80."
  type        = list(string)
}

variable "container_port" {
  description = "Port the containers listen on (target group port)."
  type        = number
}

variable "health_check_path" {
  description = "Path the ALB health-checks on each task."
  type        = string
}

variable "deregistration_delay" {
  description = "Seconds the ALB keeps draining a target before removing it (default AWS value is 300)."
  type        = number
  default     = 30
}

variable "enable_deletion_protection" {
  description = "Prevent the ALB from being deleted (true for prod)."
  type        = bool
  default     = false
}

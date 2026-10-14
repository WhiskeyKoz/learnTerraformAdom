variable "name_prefix" {
  description = "Prefix for resource names (<project>-<env>)."
  type        = string
}

variable "component" {
  description = "Optional name part, e.g. \"backend\" -> <name_prefix>-backend-alb. Empty keeps the Phase 1 names (<name_prefix>-alb)."
  type        = string
  default     = ""
}

variable "internal" {
  description = "true = internal ALB (private IPs only, not reachable from the internet)."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC the ALB and target group belong to."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets (one per AZ) to place the ALB in: public subnets for an internet-facing ALB, private subnets for an internal one."
  type        = list(string)
}

variable "ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB on HTTP 80."
  type        = list(string)
  default     = []
}

variable "ingress_security_groups" {
  description = <<-EOT
    Security groups allowed to reach the ALB on HTTP 80 (SG-to-SG rule; works across
    same-region VPC peering), as { label = sg_id }, e.g. { frontend_tasks = module.x.sg_id }.
    A map, not a list: for_each keys must be known at plan time, and SG IDs of
    not-yet-created groups are not - the static labels are.
  EOT
  type        = map(string)
  default     = {}
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

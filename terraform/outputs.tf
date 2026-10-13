output "name_prefix" {
  description = "Naming prefix applied to all resources."
  value       = local.name_prefix
}

# --- Network ---------------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB)."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs (ECS tasks)."
  value       = module.network.private_subnet_ids
}

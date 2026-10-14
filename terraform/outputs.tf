output "name_prefix" {
  description = "Naming prefix applied to all resources."
  value       = local.name_prefix
}

# --- Network: VPC A (frontend) ---------------------------------------------
output "vpc_id" {
  description = "ID of VPC A (frontend)."
  value       = module.network_frontend.vpc_id
}

output "public_subnet_ids" {
  description = "VPC A public subnet IDs (public ALB)."
  value       = module.network_frontend.public_subnet_ids
}

output "private_subnet_ids" {
  description = "VPC A private subnet IDs (frontend ECS tasks)."
  value       = module.network_frontend.private_subnet_ids
}

# --- Network: VPC B (backend) + peering -------------------------------------
output "vpc_b_id" {
  description = "ID of VPC B (backend, private-only)."
  value       = module.network_backend.vpc_id
}

output "vpc_b_private_subnet_ids" {
  description = "VPC B private subnet IDs (backend ECS tasks + internal ALB)."
  value       = module.network_backend.private_subnet_ids
}

output "peering_connection_id" {
  description = "VPC A <-> VPC B peering connection."
  value       = module.peering.peering_connection_id
}

# --- Frontend layer (VPC A) -------------------------------------------------
output "app_url" {
  description = "Open this in a browser - refresh to see requests hit tasks in both AZs."
  value       = "http://${module.alb_frontend.alb_dns_name}"
}

output "frontend_ecr_repository_url" {
  description = "Push the frontend image here: docker push <url>:<frontend_image_tag>"
  value       = module.ecr_frontend.repository_url
}

output "frontend_log_group_name" {
  description = "CloudWatch log group for the frontend containers."
  value       = aws_cloudwatch_log_group.frontend.name
}

output "frontend_ecs_cluster_name" {
  description = "Frontend ECS cluster name."
  value       = module.ecs_frontend.cluster_name
}

output "frontend_ecs_service_name" {
  description = "Frontend ECS service name."
  value       = module.ecs_frontend.service_name
}

output "frontend_tasks_security_group_id" {
  description = "Security group of the frontend tasks (the source the backend ALB will allow in Step 6)."
  value       = module.ecs_frontend.tasks_security_group_id
}

# --- Backend layer (VPC B) --------------------------------------------------
output "backend_url" {
  description = "Internal ALB URL - resolves to private IPs in VPC B, NOT reachable from the internet. The frontend gets it as BACKEND_URL."
  value       = "http://${module.alb_backend.alb_dns_name}"
}

output "backend_ecr_repository_url" {
  description = "Push the backend image here: docker push <url>:<backend_image_tag>"
  value       = module.ecr_backend.repository_url
}

output "backend_log_group_name" {
  description = "CloudWatch log group for the backend containers."
  value       = aws_cloudwatch_log_group.backend.name
}

output "backend_ecs_cluster_name" {
  description = "Backend ECS cluster name."
  value       = module.ecs_backend.cluster_name
}

output "backend_ecs_service_name" {
  description = "Backend ECS service name."
  value       = module.ecs_backend.service_name
}

output "backend_alb_security_group_id" {
  description = "Security group of the internal ALB."
  value       = module.alb_backend.alb_security_group_id
}

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

# --- ECR -------------------------------------------------------------------
output "ecr_repository_url" {
  description = "Push the app image here: docker push <url>:<image_tag>"
  value       = module.ecr.repository_url
}

# --- Logging / IAM ---------------------------------------------------------
output "log_group_name" {
  description = "CloudWatch log group for the app containers."
  value       = aws_cloudwatch_log_group.app.name
}

output "ecs_execution_role_arn" {
  description = "ECS task execution role (image pull + logs)."
  value       = module.iam.execution_role_arn
}

output "ecs_task_role_arn" {
  description = "ECS task role (app runtime identity)."
  value       = module.iam.task_role_arn
}

# --- ALB / ECS -------------------------------------------------------------
output "app_url" {
  description = "Open this in a browser - refresh to see requests hit tasks in both AZs."
  value       = "http://${module.alb.alb_dns_name}"
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = module.ecs.service_name
}

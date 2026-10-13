output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.app.name
}

output "task_definition_arn" {
  description = "ARN (with revision) of the task definition in use."
  value       = aws_ecs_task_definition.app.arn
}

output "tasks_security_group_id" {
  description = "Security group of the ECS tasks (Phase 2: allow VPC B traffic from it)."
  value       = aws_security_group.tasks.id
}

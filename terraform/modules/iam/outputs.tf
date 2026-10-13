output "execution_role_arn" {
  description = "ARN of the ECS task execution role (task definition: execution_role_arn)."
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "ARN of the ECS task role (task definition: task_role_arn)."
  value       = aws_iam_role.task.arn
}

output "execution_role_name" {
  description = "Name of the ECS task execution role."
  value       = aws_iam_role.execution.name
}

output "task_role_name" {
  description = "Name of the ECS task role."
  value       = aws_iam_role.task.name
}

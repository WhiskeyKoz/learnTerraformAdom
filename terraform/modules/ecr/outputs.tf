output "repository_name" {
  description = "Name of the ECR repository."
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "URL to tag/push images to and to reference in the task definition."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the repository (used to scope the task execution role)."
  value       = aws_ecr_repository.this.arn
}

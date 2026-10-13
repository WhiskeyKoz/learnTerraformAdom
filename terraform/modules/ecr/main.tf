# ---------------------------------------------------------------------------
# ECR module
#
# Private image repository for the application container. Access is granted
# through IAM (the ECS task execution role), so no repository policy is needed.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  name = "${var.name_prefix}-${var.repository_name}"

  # Immutable tags: v1.0.0 always means the same image, so a deployment is
  # reproducible and a tag can't be silently overwritten (supply-chain safety).
  image_tag_mutability = var.image_tag_mutability

  # Lets `terraform destroy` clean up a demo repo that still holds images.
  force_delete = var.force_delete

  # Basic vulnerability scan (OS packages, CVEs) on every push - free.
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encryption at rest. AES256 = AWS-managed keys at no extra cost; switch to
  # KMS when you need your own key policy or key-usage audit trail.
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "${var.name_prefix}-${var.repository_name}" }
}

# Lifecycle policy keeps storage cost bounded and the repo tidy.
# Rules are evaluated by priority (lowest first).
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the ${var.max_image_count} most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IAM module
#
# ECS uses two separate roles - keeping them apart is the core of
# least privilege on ECS:
#
#   Task EXECUTION role -> used by the ECS agent / Fargate *before and around*
#                          the container: pull the image, ship logs.
#   TASK role           -> used by the application code *inside* the container
#                          when it calls AWS APIs.
#
# A compromised container only ever gets the TASK role's credentials, which
# here has no permissions at all.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ---------------------------------------------------------------------------
# Trust policy (shared by both roles)
# Only ECS tasks may assume the roles, and only on behalf of ECS resources in
# THIS account and region - protects against the "confused deputy" problem.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    sid     = "AllowEcsTasksAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ecs:${var.aws_region}:${local.account_id}:*"]
    }
  }
}

# ---------------------------------------------------------------------------
# Task execution role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-ecs-execution-role"
  description        = "Lets ECS pull the app image from ECR and write container logs"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

# Custom policy instead of the AWS managed AmazonECSTaskExecutionRolePolicy:
# the managed one allows pulling from ANY repo and writing to ANY log group.
data "aws_iam_policy_document" "execution" {
  # GetAuthorizationToken is account-level - AWS does not support scoping it
  # to a resource, so "*" is the only valid value here.
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Pull image layers from THIS repository only.
  statement {
    sid    = "EcrPullAppImage"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [var.ecr_repository_arn]
  }

  # Write log streams in THIS log group only. No logs:CreateLogGroup - the
  # group is created by Terraform, not at runtime.
  statement {
    sid    = "WriteAppLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${var.log_group_arn}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "${var.name_prefix}-ecs-execution-policy"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# ---------------------------------------------------------------------------
# Task role
# ---------------------------------------------------------------------------
# Intentionally has NO policies: the app doesn't call any AWS APIs.
# Add narrowly scoped statements here only when the app needs them
# (e.g. ssmmessages:* for ECS Exec, or s3:GetObject on one bucket).
resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-ecs-task-role"
  description        = "Runtime identity of the app container (no permissions by default)"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

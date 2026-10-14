output "alb_dns_name" {
  description = "DNS name of the ALB (internal ALBs resolve to private IPs only)."
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "ARN of the ALB."
  value       = aws_lb.this.arn
}

output "alb_security_group_id" {
  description = "Security group of the ALB (the tasks SG allows ingress from it)."
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "Target group the ECS service registers tasks in."
  value       = aws_lb_target_group.app.arn

  # ECS rejects a service whose target group isn't attached to a load
  # balancer yet. Exposing the ARN only after the listener exists makes the
  # ecs module wait for it.
  depends_on = [aws_lb_listener.http]
}

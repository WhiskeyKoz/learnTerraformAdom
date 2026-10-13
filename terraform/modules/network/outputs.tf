output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs (for the ALB)."
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs (for ECS tasks)."
  value       = [for s in aws_subnet.private : s.id]
}

output "private_subnet_cidrs" {
  description = "Private subnet CIDRs."
  value       = [for s in aws_subnet.private : s.cidr_block]
}

output "public_route_table_id" {
  description = "Public route table ID."
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "Private route table ID (Phase 2 adds the peering route here)."
  value       = aws_route_table.private.id
}

output "s3_prefix_list_id" {
  description = "Managed prefix list of S3 (via the Gateway endpoint) - lets SGs allow egress to S3 only."
  value       = aws_vpc_endpoint.s3.prefix_list_id
}

output "vpc_endpoints_security_group_id" {
  description = "Security group attached to the Interface VPC endpoints."
  value       = aws_security_group.vpc_endpoints.id
}

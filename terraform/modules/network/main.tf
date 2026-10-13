# ---------------------------------------------------------------------------
# Network module
#
# One VPC with a public and a private subnet in each AZ.
#   Public  subnets -> route 0.0.0.0/0 via the Internet Gateway (ALB lives here)
#   Private subnets -> NO internet route; AWS services reached via VPC endpoints
#                      (ECS tasks live here)
#
# Written as a reusable module so Phase 2 can create VPC B with a second call.
# ---------------------------------------------------------------------------

locals {
  # Key subnets by AZ name instead of list index: with for_each, adding or
  # removing an AZ later won't shift/recreate the other subnets (as count would).
  subnets = {
    for idx, az in var.availability_zones : az => {
      public_cidr  = var.public_subnet_cidrs[idx]
      private_cidr = var.private_subnet_cidrs[idx]
    }
  }
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # Both are required for Interface endpoint private DNS: tasks resolve the
  # normal ECR/Logs hostnames, which then point at the endpoint's private IPs.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

# Lock down the VPC's default security group (no rules = deny all).
# Anything accidentally launched without an explicit SG gets no access.
# (CIS AWS Foundations Benchmark recommendation.)
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-default-sg-locked" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-igw" }
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  for_each = local.subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value.public_cidr

  # The ALB gets its public IPs from AWS regardless; nothing else in this
  # subnet should silently receive a public IP.
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-public-${each.key}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  for_each = local.subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value.private_cidr

  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-private-${each.key}"
    Tier = "private"
  }
}

# ---------------------------------------------------------------------------
# Route tables
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# One shared private route table is enough: with no NAT Gateway there is no
# per-AZ next hop to differ. It only holds the local route, the S3 gateway
# endpoint route, and (Phase 2) the VPC peering route.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-private-rt" }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------------------------
# VPC endpoints - private access to AWS services without internet/NAT
# ---------------------------------------------------------------------------

# S3 Gateway endpoint (free). Required because ECR stores image layers in S3.
# The policy limits it to ECR's layer bucket only - least privilege.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEcrImageLayersOnly"
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:GetObject"]
      Resource  = ["arn:aws:s3:::prod-${var.aws_region}-starport-layer-bucket/*"]
    }]
  })

  tags = { Name = "${var.name_prefix}-vpce-s3" }
}

# Security group for the Interface endpoints: HTTPS in, only from the private
# subnets (where the ECS tasks run). Endpoints never initiate traffic, so no
# egress rules are needed.
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name_prefix}-vpce-sg"
  description = "HTTPS from private subnets to Interface VPC endpoints"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-vpce-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https" {
  for_each = aws_subnet.private

  security_group_id = aws_security_group.vpc_endpoints.id
  description       = "HTTPS from private subnet ${each.key}"
  cidr_ipv4         = each.value.cidr_block
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# Interface endpoints (an ENI in each private subnet): ECR API, ECR Docker
# registry, and CloudWatch Logs.
resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoint_services)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.name_prefix}-vpce-${replace(each.value, ".", "-")}" }
}

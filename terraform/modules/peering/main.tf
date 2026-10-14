# ---------------------------------------------------------------------------
# Peering module
#
# Private link between two VPCs in the same account + region, plus the routes
# on BOTH sides (traffic needs a way there and a way back).
#
#   VPC A private RT:  <accepter CIDR>  -> peering
#   VPC B private RT:  <requester CIDR> -> peering
#
# Notes:
# - Routes say WHERE traffic may go; security groups still decide WHO may
#   connect. Until SG rules allow it, nothing passes.
# - Peering is NOT transitive: VPC B can't use VPC A's Internet Gateway (or
#   any other peering of VPC A). The backend stays isolated.
# - No DNS-resolution options needed: the internal ALB's DNS name is public
#   and resolves to its private IPs from anywhere.
# ---------------------------------------------------------------------------

locals {
  # Two CIDRs overlap if either one contains the other's network address.
  # "Contains": masking the address with the other block's prefix length
  # gives that block's network address.
  requester_net = cidrhost(var.requester_vpc_cidr, 0)
  accepter_net  = cidrhost(var.accepter_vpc_cidr, 0)
  requester_len = split("/", var.requester_vpc_cidr)[1]
  accepter_len  = split("/", var.accepter_vpc_cidr)[1]

  cidrs_overlap = (
    cidrhost("${local.accepter_net}/${local.requester_len}", 0) == local.requester_net ||
    cidrhost("${local.requester_net}/${local.accepter_len}", 0) == local.accepter_net
  )
}

resource "aws_vpc_peering_connection" "this" {
  vpc_id      = var.requester_vpc_id
  peer_vpc_id = var.accepter_vpc_id

  # Same account + same region: the request can be accepted immediately.
  auto_accept = true

  tags = { Name = "${var.name_prefix}-peering-a-b" }

  lifecycle {
    # AWS rejects peering between overlapping CIDRs, but only during apply,
    # possibly after other resources were already created. Fail at plan time.
    precondition {
      condition     = !local.cidrs_overlap
      error_message = "VPC CIDRs ${var.requester_vpc_cidr} and ${var.accepter_vpc_cidr} overlap - VPC peering requires non-overlapping ranges."
    }
  }
}

# Requester (VPC A) -> accepter (VPC B)
resource "aws_route" "requester_to_accepter" {
  for_each = var.requester_route_tables

  route_table_id            = each.value
  destination_cidr_block    = var.accepter_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

# Accepter (VPC B) -> requester (VPC A): the return path.
resource "aws_route" "accepter_to_requester" {
  for_each = var.accepter_route_tables

  route_table_id            = each.value
  destination_cidr_block    = var.requester_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

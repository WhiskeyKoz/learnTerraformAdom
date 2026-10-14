variable "name_prefix" {
  description = "Prefix for resource names (<project>-<env>)."
  type        = string
}

variable "requester_vpc_id" {
  description = "VPC that requests the peering (VPC A, frontend)."
  type        = string
}

variable "requester_vpc_cidr" {
  description = "CIDR of the requester VPC (routed to from the accepter side)."
  type        = string
}

variable "requester_route_tables" {
  description = <<-EOT
    Requester route tables that get a route to the accepter VPC, as { label = route_table_id }.
    Pass ONLY private route tables - public subnets must not reach the peer.
    A map with static labels: for_each keys must be known at plan time, route table IDs are not.
  EOT
  type        = map(string)
}

variable "accepter_vpc_id" {
  description = "VPC that accepts the peering (VPC B, backend)."
  type        = string
}

variable "accepter_vpc_cidr" {
  description = "CIDR of the accepter VPC (routed to from the requester side)."
  type        = string
}

variable "accepter_route_tables" {
  description = "Accepter route tables that get a route back to the requester VPC, as { label = route_table_id }."
  type        = map(string)
}

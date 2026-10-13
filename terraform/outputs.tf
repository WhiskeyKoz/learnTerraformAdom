# Outputs are added as each module is wired in (e.g. alb_dns_name,
# ecr_repository_url). Kept minimal until then.

output "name_prefix" {
  description = "Naming prefix applied to all resources."
  value       = local.name_prefix
}

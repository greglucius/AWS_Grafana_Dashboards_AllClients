output "grafana_workspace_endpoint" {
  description = "Amazon Managed Grafana workspace URL"
  value       = module.hub.grafana_workspace_endpoint
}

output "grafana_workspace_id" {
  description = "Amazon Managed Grafana workspace ID"
  value       = module.hub.grafana_workspace_id
}

output "hub_grafana_role_arn" {
  description = "ARN of the hub Grafana IAM role (used in spoke trust policies)"
  value       = module.hub.grafana_role_arn
}

output "spoke_role_arns" {
  description = "Map of spoke account names to their GrafanaCloudWatchAccessRole ARNs"
  value       = { for k, v in module.spoke : k => v.spoke_role_arn }
}

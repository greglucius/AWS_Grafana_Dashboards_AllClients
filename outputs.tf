output "grafana_cloud_stack_url" {
  description = "Grafana Cloud stack URL (as configured)"
  value       = var.grafana_cloud_stack_url
}

output "spoke_role_arns" {
  description = "Map of spoke account names to their GrafanaCloudWatchAccessRole ARNs"
  value       = { for k, v in module.spoke : k => v.spoke_role_arn }
}

output "external_id" {
  description = "External ID used in spoke trust policies and data-source configuration. Store this securely."
  value       = local.external_id
  sensitive   = true
}

output "data_source_names" {
  description = "Names of the provisioned CloudWatch data sources"
  value       = [for ds in grafana_data_source.cloudwatch : ds.name]
}

output "grafana_workspace_endpoint" {
  description = "The endpoint URL of the Amazon Managed Grafana workspace"
  value       = aws_grafana_workspace.this.endpoint
}

output "grafana_workspace_id" {
  description = "The ID of the Amazon Managed Grafana workspace"
  value       = aws_grafana_workspace.this.id
}

output "grafana_role_arn" {
  description = "ARN of the GrafanaWorkspaceRole (used in spoke trust policies)"
  value       = aws_iam_role.grafana_workspace.arn
}

output "spoke_role_arn" {
  description = "ARN of the GrafanaCloudWatchAccessRole in this spoke account"
  value       = aws_iam_role.grafana_cloudwatch.arn
}

output "spoke_role_name" {
  description = "Name of the GrafanaCloudWatchAccessRole in this spoke account"
  value       = aws_iam_role.grafana_cloudwatch.name
}

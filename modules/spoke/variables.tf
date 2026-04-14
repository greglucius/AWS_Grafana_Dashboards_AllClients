variable "grafana_cloud_aws_account_id" {
  description = "AWS account ID of Grafana Labs' Grafana Cloud service. Defaults to the documented production account."
  type        = string
  default     = "008923505280"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.grafana_cloud_aws_account_id))
    error_message = "grafana_cloud_aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "external_id" {
  description = "External ID required in the trust policy. Grafana Cloud uses this to prevent confused-deputy attacks. Must match the externalId configured on the CloudWatch data source."
  type        = string

  validation {
    condition     = length(var.external_id) >= 8
    error_message = "external_id must be at least 8 characters. Use a UUID or other high-entropy value."
  }
}

variable "role_name" {
  description = "Name of the IAM role created in the spoke account"
  type        = string
  default     = "GrafanaCloudWatchAccessRole"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

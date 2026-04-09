variable "spoke_account_ids" {
  description = "List of spoke (client) AWS account IDs that the Grafana role can assume into"
  type        = list(string)

  validation {
    condition     = alltrue([for id in var.spoke_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "Each spoke account ID must be a 12-digit AWS account ID."
  }
}

variable "grafana_role_name" {
  description = "Name of the IAM role assigned to the Grafana workspace"
  type        = string
  default     = "GrafanaWorkspaceRole"
}

variable "spoke_role_name" {
  description = "Name of the IAM role in spoke accounts that Grafana will assume"
  type        = string
  default     = "GrafanaCloudWatchAccessRole"
}

variable "workspace_name" {
  description = "Name for the Amazon Managed Grafana workspace"
  type        = string
  default     = "observability-hub"
}

variable "sso_admin_group_ids" {
  description = "IAM Identity Center group IDs granted ADMIN access to the Grafana workspace"
  type        = list(string)
  default     = []
}

variable "sso_editor_group_ids" {
  description = "IAM Identity Center group IDs granted EDITOR access to the Grafana workspace"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

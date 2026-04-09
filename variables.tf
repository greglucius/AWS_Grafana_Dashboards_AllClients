variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "hub_aws_profile" {
  description = "AWS CLI profile for the hub (MSP) account"
  type        = string
}

variable "hub_account_id" {
  description = "AWS account ID of the hub (MSP) account"
  type        = string
}

variable "spoke_accounts" {
  description = "Map of spoke client accounts. Key is a friendly name, value is the account ID."
  type        = map(string)

  validation {
    condition     = length(var.spoke_accounts) > 0
    error_message = "At least one spoke account must be provided."
  }
}

variable "grafana_api_key" {
  description = "Grafana workspace API key for data source provisioning (generate after first apply)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "sso_admin_group_ids" {
  description = "List of AWS IAM Identity Center (SSO) group IDs to grant Grafana ADMIN role"
  type        = list(string)
  default     = []
}

variable "sso_editor_group_ids" {
  description = "List of AWS IAM Identity Center (SSO) group IDs to grant Grafana EDITOR role"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "observability-hub-spoke"
    ManagedBy = "terraform"
  }
}

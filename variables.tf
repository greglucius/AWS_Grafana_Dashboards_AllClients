variable "aws_region" {
  description = "Default AWS region for CloudWatch queries"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile used to create spoke IAM roles. Typically the management/org profile with access into each client account."
  type        = string
  default     = null
}

variable "spoke_accounts" {
  description = "Map of spoke client accounts. Key is a friendly name, value is the account ID."
  type        = map(string)

  validation {
    condition     = length(var.spoke_accounts) > 0
    error_message = "At least one spoke account must be provided."
  }

  validation {
    condition     = alltrue([for id in values(var.spoke_accounts) : can(regex("^[0-9]{12}$", id))])
    error_message = "Each spoke account value must be a 12-digit AWS account ID."
  }
}

# ---------- Grafana Cloud ----------

variable "grafana_cloud_stack_url" {
  description = "URL of your Grafana Cloud stack (e.g. https://mycompany.grafana.net)"
  type        = string

  validation {
    condition     = can(regex("^https://", var.grafana_cloud_stack_url))
    error_message = "grafana_cloud_stack_url must start with https://"
  }
}

variable "grafana_cloud_stack_sa_token" {
  description = "Grafana Cloud stack service account token (Admin role). Create one at Administration → Service accounts."
  type        = string
  sensitive   = true
}

variable "grafana_cloud_aws_account_id" {
  description = "AWS account ID of Grafana Labs' Grafana Cloud service. Defaults to the documented production account."
  type        = string
  default     = "008923505280"
}

variable "external_id" {
  description = "External ID used in spoke trust policies and the CloudWatch data source. If empty, a random UUID is generated and stored in state."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to all AWS resources"
  type        = map(string)
  default = {
    Project   = "observability-hub-spoke"
    ManagedBy = "terraform"
  }
}

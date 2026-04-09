variable "hub_grafana_role_arn" {
  description = "ARN of the Grafana workspace IAM role in the hub account that is allowed to assume this spoke role"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.hub_grafana_role_arn))
    error_message = "hub_grafana_role_arn must be a valid IAM role ARN."
  }
}

variable "role_name" {
  description = "Name of the IAM role created in the spoke account"
  type        = string
  default     = "GrafanaCloudWatchAccessRole"
}

variable "external_id" {
  description = "Optional external ID for additional cross-account security"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

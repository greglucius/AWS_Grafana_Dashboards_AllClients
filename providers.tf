terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# AWS provider — used for spoke IAM roles. Assumes the caller has credentials
# that can create IAM in each spoke account (e.g. via OrganizationAccountAccessRole
# or per-account profile aliases — see README for multi-account strategies).
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# Grafana provider — points at an existing Grafana Cloud stack.
# Generate a service-account token from your stack (Administration →
# Service accounts) and pass it in via the grafana_cloud_stack_sa_token variable.
provider "grafana" {
  url  = var.grafana_cloud_stack_url
  auth = var.grafana_cloud_stack_sa_token
}

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
  }
}

# Hub account provider — used for Grafana workspace and hub IAM
provider "aws" {
  alias   = "hub"
  region  = var.aws_region
  profile = var.hub_aws_profile
}

# Grafana provider — configured after workspace is created
provider "grafana" {
  url  = "https://${module.hub.grafana_workspace_endpoint}"
  auth = var.grafana_api_key
}

# -----------------------------------------------------------------------------
# Hub Module — Central MSP Account (Grafana Workspace + IAM)
# -----------------------------------------------------------------------------
module "hub" {
  source = "./modules/hub"

  providers = {
    aws = aws.hub
  }

  spoke_account_ids   = values(var.spoke_accounts)
  sso_admin_group_ids = var.sso_admin_group_ids
  tags                = var.tags
}

# -----------------------------------------------------------------------------
# Spoke Modules — One per client account
# Each spoke creates an IAM role that the hub Grafana role can assume.
# Deploy these with per-account AWS provider aliases (see README).
# -----------------------------------------------------------------------------
module "spoke" {
  source   = "./modules/spoke"
  for_each = var.spoke_accounts

  hub_grafana_role_arn = module.hub.grafana_role_arn
  tags                 = var.tags
}

# -----------------------------------------------------------------------------
# Grafana CloudWatch Data Sources — one per spoke
# Only created when a grafana_api_key is supplied (second apply).
# -----------------------------------------------------------------------------
resource "grafana_data_source" "cloudwatch" {
  for_each = var.grafana_api_key != "" ? var.spoke_accounts : {}

  type = "cloudwatch"
  name = "CloudWatch-${each.key}"

  json_data_encoded = jsonencode({
    defaultRegion = var.aws_region
    authType      = "assumeRole"
    assumeRoleArn = module.spoke[each.key].spoke_role_arn
    customMetricsNamespaces = ""
    # CRITICAL: 600 s minimum polling interval to prevent aggressive
    # GetMetricData calls that spike client AWS bills.
    timeInterval = "600s"
  })
}

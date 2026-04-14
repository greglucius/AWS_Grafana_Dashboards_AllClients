# -----------------------------------------------------------------------------
# Hub-and-Spoke Observability with Grafana Cloud
#
#  • Spoke IAM roles (one per client account) trust Grafana Labs' production
#    AWS account, gated by an External ID for confused-deputy protection.
#  • Grafana Cloud CloudWatch data sources (one per spoke) configured with
#    authType = grafana_assume_role, the spoke role ARN, and timeInterval 600s.
# -----------------------------------------------------------------------------

# Generate a stable external ID if the caller didn't provide one.
resource "random_uuid" "external_id" {
  count = var.external_id == "" ? 1 : 0
}

locals {
  external_id = var.external_id != "" ? var.external_id : random_uuid.external_id[0].result
}

# -----------------------------------------------------------------------------
# Spoke Modules — One IAM role per client account.
# Each spoke module needs AWS creds for its target account. See README for the
# two supported deployment patterns (provider aliases vs. separate workspaces).
# -----------------------------------------------------------------------------
module "spoke" {
  source   = "./modules/spoke"
  for_each = var.spoke_accounts

  grafana_cloud_aws_account_id = var.grafana_cloud_aws_account_id
  external_id                  = local.external_id
  tags                         = var.tags
}

# -----------------------------------------------------------------------------
# Grafana Cloud CloudWatch Data Sources — one per spoke.
# -----------------------------------------------------------------------------
resource "grafana_data_source" "cloudwatch" {
  for_each = var.spoke_accounts

  type = "cloudwatch"
  name = "CloudWatch-${each.key}"

  json_data_encoded = jsonencode({
    defaultRegion = var.aws_region
    # "grafana_assume_role" tells Grafana Cloud to chain-assume through
    # Grafana Labs' AWS account into the customer role.
    authType                = "grafana_assume_role"
    assumeRoleArn           = module.spoke[each.key].spoke_role_arn
    externalId              = local.external_id
    customMetricsNamespaces = ""
    # CRITICAL: 600 s minimum polling interval prevents aggressive
    # GetMetricData calls that would spike client AWS bills.
    timeInterval = "600s"
  })
}

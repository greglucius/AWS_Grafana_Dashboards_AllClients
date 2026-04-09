# -----------------------------------------------------------------------------
# Hub Module — Deployed in the central MSP account
#
# Creates an Amazon Managed Grafana workspace with an IAM role that can
# assume the GrafanaCloudWatchAccessRole in each spoke account.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# --------------- IAM: Grafana Workspace Role ---------------

data "aws_iam_policy_document" "grafana_assume" {
  statement {
    sid     = "AllowGrafanaServiceAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "grafana_workspace" {
  name               = var.grafana_role_name
  assume_role_policy = data.aws_iam_policy_document.grafana_assume.json
  tags               = var.tags
}

# Custom policy: allow the Grafana role to assume spoke CloudWatch roles
data "aws_iam_policy_document" "assume_spoke_roles" {
  statement {
    sid    = "AllowAssumeSpokeCloudWatchRoles"
    effect = "Allow"
    actions = [
      "sts:AssumeRole"
    ]
    resources = [
      for acct_id in var.spoke_account_ids :
      "arn:aws:iam::${acct_id}:role/${var.spoke_role_name}"
    ]
  }
}

resource "aws_iam_policy" "assume_spoke_roles" {
  name        = "${var.grafana_role_name}-AssumeSpokeRoles"
  description = "Allows the Grafana workspace role to assume CloudWatch access roles in spoke accounts"
  policy      = data.aws_iam_policy_document.assume_spoke_roles.json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "assume_spoke_roles" {
  role       = aws_iam_role.grafana_workspace.name
  policy_arn = aws_iam_policy.assume_spoke_roles.arn
}

# --------------- Amazon Managed Grafana Workspace ---------------

resource "aws_grafana_workspace" "this" {
  name                     = var.workspace_name
  description              = "Central observability hub for multi-account CloudWatch monitoring"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana_workspace.arn

  data_sources = [
    "CLOUDWATCH"
  ]

  tags = var.tags
}

# --------------- SSO Role Associations (optional) ---------------

resource "aws_grafana_role_association" "admin" {
  for_each = toset(var.sso_admin_group_ids)

  role         = "ADMIN"
  group_ids    = [each.value]
  workspace_id = aws_grafana_workspace.this.id
}

resource "aws_grafana_role_association" "editor" {
  for_each = toset(var.sso_editor_group_ids)

  role         = "EDITOR"
  group_ids    = [each.value]
  workspace_id = aws_grafana_workspace.this.id
}

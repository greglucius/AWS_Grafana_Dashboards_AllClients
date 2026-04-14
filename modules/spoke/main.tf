# -----------------------------------------------------------------------------
# Spoke Module — Deployed in each client AWS account
#
# Creates an IAM Role that Grafana Cloud (running in Grafana Labs' AWS account)
# can assume to read CloudWatch metrics, logs, and alarms.
#
# Security model: Grafana Cloud performs a "grafana-assume-role" chain where
# Grafana Labs' production AWS account assumes this role, gated by an external
# ID unique to the Grafana Cloud stack (confused-deputy protection).
#
# Reference: https://grafana.com/docs/grafana/latest/datasources/aws-cloudwatch/aws-authentication/
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "AllowGrafanaCloudAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.grafana_cloud_aws_account_id}:root"]
    }

    # External ID is REQUIRED for Grafana Cloud — this is how Grafana Labs
    # prevents confused-deputy attacks against customer accounts.
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
    }
  }
}

resource "aws_iam_role" "grafana_cloudwatch" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cloudwatch_readonly" {
  role       = aws_iam_role.grafana_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

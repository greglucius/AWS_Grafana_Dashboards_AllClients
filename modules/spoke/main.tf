# -----------------------------------------------------------------------------
# Spoke Module — Deployed in each client AWS account
#
# Creates an IAM Role that the hub Grafana workspace can assume to read
# CloudWatch metrics, logs, and alarms.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "AllowHubGrafanaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.hub_grafana_role_arn]
    }

    # Optional external ID for defence-in-depth
    dynamic "condition" {
      for_each = var.external_id != "" ? [var.external_id] : []
      content {
        test     = "StringEquals"
        variable = "sts:ExternalId"
        values   = [condition.value]
      }
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

# Retention is a variable (dev 14 days, prod 90 days): WAF logs hold client IPs, so they are kept as short as the
# operations need (GDPR minimisation, security steering).
resource "aws_cloudwatch_log_group" "waf" {
  # checkov:skip=CKV_AWS_338: Retention follows the iac steering (dev 14 days, prod 90 days) and GDPR data minimisation; one year is not wanted for logs that contain client IP addresses.
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = local.log_group_name })
}

# Confused-deputy protection: only the log delivery service acting in this account and region can write.
data "aws_iam_policy_document" "log_delivery" {
  statement {
    sid       = "AllowWafLogDelivery"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.waf.arn}:*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    # AWS WAF log delivery to CloudWatch Logs presents a logs-service source ARN (not the web ACL ARN), so the
    # condition is pinned to the logs ARNs of this account and region; aws:SourceAccount narrows it to this account.
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "waf" {
  count = var.enable_log_resource_policy ? 1 : 0

  policy_name     = local.log_group_name
  policy_document = data.aws_iam_policy_document.log_delivery.json
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  dynamic "redacted_fields" {
    for_each = local.redacted_headers

    content {
      single_header {
        name = redacted_fields.value
      }
    }
  }

  # The Cognito callback (?code=...) is served through CloudFront: the query string never reaches the logs there.
  dynamic "redacted_fields" {
    for_each = var.scope == "CLOUDFRONT" ? [1] : []

    content {
      query_string {}
    }
  }

  depends_on = [aws_cloudwatch_log_resource_policy.waf]
}

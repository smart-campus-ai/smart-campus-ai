resource "aws_cloudwatch_log_group" "trail" {
  # checkov:skip=CKV_AWS_338: Retention follows the environment policy (dev 14 days, prod 90 days); the one-year copy of the logs is the log bucket (log_bucket_expiration_days).
  count = var.enable_cloudtrail ? 1 : 0

  name              = "/aws/cloudtrail/${local.trail_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = "/aws/cloudtrail/${local.trail_name}" })
}

# The trail ARN is built from names instead of the trail attribute: the role is a dependency of the trail.
data "aws_iam_policy_document" "trail_assume" {
  count = var.enable_cloudtrail ? 1 : 0

  statement {
    sid     = "CloudTrailAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

data "aws_iam_policy_document" "trail_logs" {
  count = var.enable_cloudtrail ? 1 : 0

  statement {
    sid       = "WriteTrailLogStreams"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.trail[0].arn}:log-stream:*"]
  }
}

resource "aws_iam_role" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  name                 = "${var.name_prefix}-cloudtrail-logs"
  assume_role_policy   = data.aws_iam_policy_document.trail_assume[0].json
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(var.tags, { Name = "${var.name_prefix}-cloudtrail-logs" })
}

resource "aws_iam_role_policy" "trail" {
  count = var.enable_cloudtrail ? 1 : 0

  name   = "write-trail-logs"
  role   = aws_iam_role.trail[0].id
  policy = data.aws_iam_policy_document.trail_logs[0].json
}

resource "aws_cloudtrail" "this" {
  # checkov:skip=CKV_AWS_252: No SNS topic: trail activity is watched through the CloudWatch log group and the detection services (EN-16), not through per-file notifications.
  count = var.enable_cloudtrail ? 1 : 0

  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.logs[0].id
  s3_key_prefix  = local.trail_log_prefix
  kms_key_id     = var.kms_key_arn

  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.trail[0].arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.trail[0].arn

  # Advanced event selectors replace the default selector: management events must then be listed explicitly,
  # otherwise the trail would stop recording them.
  dynamic "advanced_event_selector" {
    for_each = var.enable_cloudtrail_s3_data_events ? [1] : []

    content {
      name = "Management events"

      field_selector {
        field  = "eventCategory"
        equals = ["Management"]
      }
    }
  }

  dynamic "advanced_event_selector" {
    for_each = var.enable_cloudtrail_s3_data_events ? [1] : []

    content {
      name = "S3 object data events"

      field_selector {
        field  = "eventCategory"
        equals = ["Data"]
      }

      field_selector {
        field  = "resources.type"
        equals = ["AWS::S3::Object"]
      }

      field_selector {
        field       = "resources.ARN"
        starts_with = [for arn in var.cloudtrail_s3_data_event_bucket_arns : "${arn}/"]
      }
    }
  }

  tags = merge(var.tags, { Name = local.trail_name })

  depends_on = [
    aws_s3_bucket_policy.logs,
    aws_iam_role_policy.trail,
  ]
}

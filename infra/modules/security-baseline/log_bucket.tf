# Dedicated bucket for the account trail and the Config deliveries. Created when either is enabled.
# Server access logging is not enabled: the bucket only receives writes from the AWS services named in its policy, and
# object-level activity on it is part of the trail itself.
#trivy:ignore:AVD-AWS-0089
resource "aws_s3_bucket" "logs" {
  # checkov:skip=CKV_AWS_18: This bucket holds the audit logs; access logging on it would need another log bucket and the trail already records its API activity.
  # checkov:skip=CKV_AWS_144: Cross-region replication is out of scope: single-region workshop (ADR-0002); versioning and retention protect against overwrite and deletion.
  # checkov:skip=CKV2_AWS_62: Event notifications are not needed on the log bucket; no consumer reacts to log delivery.
  count = local.create_log_bucket ? 1 : 0

  bucket        = local.log_bucket_name
  force_destroy = false

  tags = merge(var.tags, { Name = local.log_bucket_name })
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  # Versioning must be enabled before noncurrent version rules are meaningful.
  depends_on = [aws_s3_bucket_versioning.logs]

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_bucket_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.log_bucket_noncurrent_version_expiration_days
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  count = local.create_log_bucket ? 1 : 0

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [local.log_bucket_arn, "${local.log_bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "DenyOutdatedTls"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [local.log_bucket_arn, "${local.log_bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }

  # Objects written with another KMS key are refused. A request without the header is not refused (IfExists): the
  # bucket default encryption then applies the logs key.
  statement {
    sid       = "DenyWrongKmsKey"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${local.log_bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [var.kms_key_arn]
    }
  }

  dynamic "statement" {
    for_each = var.enable_cloudtrail ? [1] : []

    content {
      sid       = "CloudTrailAclCheck"
      effect    = "Allow"
      actions   = ["s3:GetBucketAcl"]
      resources = [local.log_bucket_arn]

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

  dynamic "statement" {
    for_each = var.enable_cloudtrail ? [1] : []

    content {
      sid       = "CloudTrailWrite"
      effect    = "Allow"
      actions   = ["s3:PutObject"]
      resources = [local.trail_log_path]

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

      condition {
        test     = "StringEquals"
        variable = "s3:x-amz-acl"
        values   = ["bucket-owner-full-control"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_config ? [1] : []

    content {
      sid       = "ConfigBucketCheck"
      effect    = "Allow"
      actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
      resources = [local.log_bucket_arn]

      principals {
        type        = "Service"
        identifiers = ["config.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = [local.config_recorder_arn]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_config ? [1] : []

    content {
      sid       = "ConfigWrite"
      effect    = "Allow"
      actions   = ["s3:PutObject"]
      resources = [local.config_log_path]

      principals {
        type        = "Service"
        identifiers = ["config.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = [local.config_recorder_arn]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }

      condition {
        test     = "StringEquals"
        variable = "s3:x-amz-acl"
        values   = ["bucket-owner-full-control"]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  count = local.create_log_bucket ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id
  policy = data.aws_iam_policy_document.bucket[0].json

  # Avoid racing the public access block update on the same bucket.
  depends_on = [aws_s3_bucket_public_access_block.logs]
}

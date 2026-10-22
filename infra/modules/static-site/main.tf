# The SPA bucket is private: the only reader is the CloudFront distribution, through OAC.
# Access logging is optional (logging_bucket_name); object-level activity is covered by the account CloudTrail.
#trivy:ignore:AVD-AWS-0089
resource "aws_s3_bucket" "site" {
  # checkov:skip=CKV_AWS_18: Server access logging is optional (logging_bucket_name); the log bucket belongs to the observability brick and is wired by the stack.
  # checkov:skip=CKV_AWS_144: Cross-region replication is out of scope: single-region workshop (ADR-0002); the SPA is rebuilt from source and versioning protects against overwrite.
  # checkov:skip=CKV2_AWS_62: Event notifications are not needed on the SPA bucket; no consumer reacts to deployments.
  bucket        = local.bucket_name
  force_destroy = false

  tags = merge(var.tags, { Name = local.bucket_name })
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  # Versioning must be enabled before noncurrent version rules are meaningful.
  depends_on = [aws_s3_bucket_versioning.site]

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    # Removes the delete markers left once the noncurrent versions of a deleted file have expired.
    expiration {
      expired_object_delete_marker = true
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

resource "aws_s3_bucket_logging" "site" {
  count = local.logging_enabled ? 1 : 0

  bucket        = aws_s3_bucket.site.id
  target_bucket = var.logging_bucket_name
  target_prefix = local.s3_access_log_prefix
}

data "aws_iam_policy_document" "bucket" {
  # Only this distribution can read: the aws:SourceArn condition stops any other CloudFront distribution (confused deputy).
  statement {
    sid       = "AllowCloudFrontRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.site.arn, "${aws_s3_bucket.site.arn}/*"]

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
    resources = [aws_s3_bucket.site.arn, "${aws_s3_bucket.site.arn}/*"]

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
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.bucket.json

  # Avoid racing the public access block update on the same bucket.
  depends_on = [aws_s3_bucket_public_access_block.site]
}

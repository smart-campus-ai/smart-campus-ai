# Student attachments (images) uploaded straight from the browser with a presigned POST built by "tickets".
# Object-level activity is covered by the account CloudTrail from the security baseline.
#trivy:ignore:AVD-AWS-0089
resource "aws_s3_bucket" "attachments" {
  # checkov:skip=CKV_AWS_18: Access logging needs a log bucket owned by another module; object-level activity is covered by the account CloudTrail from the security baseline.
  # checkov:skip=CKV_AWS_144: Cross-region replication is out of scope: single-region workshop (ADR-0002); versioning and noncurrent retention protect against overwrite and deletion.
  # checkov:skip=CKV2_AWS_62: GuardDuty Malware Protection manages its own EventBridge rules on this bucket; no other consumer needs event notifications.
  bucket        = local.bucket_name
  force_destroy = false

  tags = merge(var.tags, { Name = local.bucket_name })
}

resource "aws_s3_bucket_public_access_block" "attachments" {
  bucket = aws_s3_bucket.attachments.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "attachments" {
  bucket = aws_s3_bucket.attachments.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "attachments" {
  bucket = aws_s3_bucket.attachments.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "attachments" {
  bucket = aws_s3_bucket.attachments.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

# Same-origin through CloudFront does not apply to S3: the browser talks to the bucket directly, so CORS is limited
# to the SPA origins and to the two methods used: POST (presigned POST upload, the only upload path) and GET
# (presigned download). PUT is deliberately not allowed: it would bypass the POST policy conditions.
resource "aws_s3_bucket_cors_configuration" "attachments" {
  bucket = aws_s3_bucket.attachments.id

  cors_rule {
    allowed_origins = var.allowed_origins
    allowed_methods = ["GET", "POST"]
    allowed_headers = ["Content-Type", "x-amz-*"]
    expose_headers  = ["ETag"]
    max_age_seconds = var.cors_max_age_seconds
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "attachments" {
  bucket = aws_s3_bucket.attachments.id

  # Versioning must be enabled before noncurrent version rules are meaningful.
  depends_on = [aws_s3_bucket_versioning.attachments]

  # Every rule carries abort_incomplete_multipart_upload (CKV_AWS_300), so failed uploads are cleaned up whichever
  # rule applies to the object.
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  rule {
    id     = "remove-expired-delete-markers"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }

    expiration {
      expired_object_delete_marker = true
    }
  }

  dynamic "rule" {
    for_each = var.quarantine_expiration_days == null ? [] : [var.quarantine_expiration_days]

    content {
      id     = "expire-quarantine"
      status = "Enabled"

      filter {
        prefix = var.quarantine_prefix
      }

      abort_incomplete_multipart_upload {
        days_after_initiation = var.abort_incomplete_multipart_upload_days
      }

      expiration {
        days = rule.value
      }
    }
  }

  rule {
    id     = "expire-attachments"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }

    expiration {
      days = var.object_expiration_days
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [local.bucket_arn, local.bucket_objects_arn]

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
    resources = [local.bucket_arn, local.bucket_objects_arn]

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

  # "IfExists": a request without the header is encrypted by the bucket default (the data key), which is what a
  # presigned POST does; a request that names another algorithm or another key is refused.
  statement {
    sid       = "DenyNonKmsEncryptionHeader"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = [local.bucket_objects_arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  statement {
    sid       = "DenyOtherKmsKey"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = [local.bucket_objects_arn]

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

  # SSE-C requests carry no x-amz-server-side-encryption header, so the two IfExists statements above let them
  # through. An object written with a customer-provided key could not be scanned nor served.
  statement {
    sid       = "DenySSEC"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = [local.bucket_objects_arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption-customer-algorithm"
      values   = ["false"]
    }
  }

  # Only objects that GuardDuty tagged clean are served. A negated operator is true when the tag is missing, so an
  # object not scanned yet is refused too. The scanner role is excluded: it must read the object to scan it.
  dynamic "statement" {
    for_each = var.enable_malware_protection ? [1] : []

    content {
      sid       = "DenyReadOfUnscannedObjects"
      effect    = "Deny"
      actions   = ["s3:GetObject", "s3:GetObjectVersion"]
      resources = [local.bucket_objects_arn]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "StringNotEquals"
        variable = "s3:ExistingObjectTag/${local.scan_status_tag_key}"
        values   = [local.scan_status_clean_tag]
      }

      condition {
        test     = "ArnNotEquals"
        variable = "aws:PrincipalArn"
        values   = [local.malware_role_arn]
      }
    }
  }

  # A presigned POST can carry a "tagging" field: without this statement a student could upload a file already
  # tagged as clean and skip the scan result.
  dynamic "statement" {
    for_each = var.enable_malware_protection ? [1] : []

    content {
      sid       = "DenyForgedScanTagOnPut"
      effect    = "Deny"
      actions   = ["s3:PutObject", "s3:PutObjectVersionTagging", "s3:PutObjectTagging"]
      resources = [local.bucket_objects_arn]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "ForAnyValue:StringEquals"
        variable = "s3:RequestObjectTagKeys"
        values   = [local.scan_status_tag_key]
      }

      condition {
        test     = "ArnNotEquals"
        variable = "aws:PrincipalArn"
        values   = [local.malware_role_arn]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_malware_protection ? [1] : []

    content {
      sid       = "DenyScanTagRemoval"
      effect    = "Deny"
      actions   = ["s3:DeleteObjectTagging", "s3:DeleteObjectVersionTagging"]
      resources = [local.bucket_objects_arn]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "ArnNotEquals"
        variable = "aws:PrincipalArn"
        values   = [local.malware_role_arn]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "attachments" {
  bucket = aws_s3_bucket.attachments.id
  policy = data.aws_iam_policy_document.bucket.json

  # Avoid racing the public access block update on the same bucket.
  depends_on = [aws_s3_bucket_public_access_block.attachments]
}

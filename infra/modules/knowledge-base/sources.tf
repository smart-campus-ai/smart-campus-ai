# Source documents bucket. Writes come from the application pipeline only (writer_principal_arns); the knowledge base
# service role reads it. Object events go to the kb-sync function (see ingestion.tf, AC4).
#
# Access logging is not configured: no log bucket exists yet, and object-level activity is covered by the account
# CloudTrail from the security baseline (same exception as the state backend).
#trivy:ignore:AVD-AWS-0089
resource "aws_s3_bucket" "sources" {
  # checkov:skip=CKV_AWS_18: Access logging is optional and off (no log bucket yet); object-level activity is covered by the account CloudTrail from the security baseline.
  # checkov:skip=CKV_AWS_144: Cross-region replication is out of scope: single-region workshop (ADR-0002); versioning protects against overwrite and deletion, and the documents can be re-uploaded.
  bucket        = local.source_bucket_name
  force_destroy = false

  tags = merge(var.tags, { Name = local.source_bucket_name })
}

resource "aws_s3_bucket_public_access_block" "sources" {
  bucket = aws_s3_bucket.sources.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "sources" {
  bucket = aws_s3_bucket.sources.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "sources" {
  bucket = aws_s3_bucket.sources.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sources" {
  bucket = aws_s3_bucket.sources.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "sources" {
  bucket = aws_s3_bucket.sources.id

  # Versioning must be enabled before noncurrent version rules are meaningful.
  depends_on = [aws_s3_bucket_versioning.sources]

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  rule {
    id     = "expire-delete-markers"
    status = "Enabled"

    filter {}

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

data "aws_iam_policy_document" "sources_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.sources.arn, "${aws_s3_bucket.sources.arn}/*"]

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
    resources = [aws_s3_bucket.sources.arn, "${aws_s3_bucket.sources.arn}/*"]

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

  # "IfExists": a request without the header is encrypted by the bucket default (the ai key); a request that names
  # another algorithm or another key is refused. Clients must therefore pass the key as a full ARN.
  statement {
    sid       = "DenyNonKmsEncryptionHeader"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.sources.arn}/*"]

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
    resources = ["${aws_s3_bucket.sources.arn}/*"]

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
  # through. An object written with a customer-provided key could not be read by the knowledge base.
  statement {
    sid       = "DenySSEC"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.sources.arn}/*"]

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

  # What the knowledge base ingests is what the writers upload: nobody else may add, change or delete documents,
  # whatever their IAM permissions are.
  statement {
    sid       = "DenyWritesExceptWriters"
    effect    = "Deny"
    resources = ["${aws_s3_bucket.sources.arn}/*"]

    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectTagging",
      "s3:DeleteObjectVersion",
      "s3:DeleteObjectVersionTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:PutObjectVersionTagging",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = var.writer_principal_arns
    }
  }
}

resource "aws_s3_bucket_policy" "sources" {
  bucket = aws_s3_bucket.sources.id
  policy = data.aws_iam_policy_document.sources_bucket.json

  # Avoid racing the public access block update on the same bucket.
  depends_on = [aws_s3_bucket_public_access_block.sources]
}

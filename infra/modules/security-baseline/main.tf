# Account-level hardening and detection that needs no log bucket. CloudTrail, Config, GuardDuty and Security Hub live
# in their own files.

resource "aws_s3_account_public_access_block" "this" {
  count = var.enable_s3_account_public_access_block ? 1 : 0

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ebs_encryption_by_default" "this" {
  count = var.enable_ebs_default_encryption ? 1 : 0

  enabled = true
}

resource "aws_iam_account_password_policy" "this" {
  count = var.enable_iam_password_policy ? 1 : 0

  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
  hard_expiry                    = false
}

resource "aws_accessanalyzer_analyzer" "this" {
  count = var.enable_access_analyzer ? 1 : 0

  analyzer_name = "${var.name_prefix}-account"
  type          = "ACCOUNT"

  tags = merge(var.tags, { Name = "${var.name_prefix}-account" })
}

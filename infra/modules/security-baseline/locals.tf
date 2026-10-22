data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  # Trail and Config share one dedicated bucket, so it exists when either of them is enabled.
  create_log_bucket = var.enable_cloudtrail || var.enable_config

  # S3 bucket names are global: the account ID keeps the name unique without any hardcoded value.
  log_bucket_name = "${var.name_prefix}-security-logs-${local.account_id}"
  log_bucket_arn  = "arn:${local.partition}:s3:::${local.log_bucket_name}"

  trail_name       = "${var.name_prefix}-trail"
  trail_arn        = "arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.trail_name}"
  trail_log_prefix = "cloudtrail"
  trail_log_path   = "${local.log_bucket_arn}/${local.trail_log_prefix}/AWSLogs/${local.account_id}/*"

  config_log_prefix = "config"
  config_log_path   = "${local.log_bucket_arn}/${local.config_log_prefix}/AWSLogs/${local.account_id}/Config/*"
  config_role_arn   = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"

  # Config recorder ARN for the confused-deputy condition in the bucket policy.
  config_recorder_name = "${var.name_prefix}-config"
  config_recorder_arn  = "arn:${local.partition}:config:${local.region}:${local.account_id}:config-recorder/${local.config_recorder_name}"

  fsbp_standards_arn = "arn:${local.partition}:securityhub:${local.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

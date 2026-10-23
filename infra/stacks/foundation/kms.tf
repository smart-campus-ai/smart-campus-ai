data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # The logs key is usable by CloudWatch Logs only for log groups whose name matches these patterns. Every platform
  # log group must be named under one of them (all carry the environment prefix: the account is shared by dev and prod).
  log_group_name_patterns = [
    "/aws/lambda/${var.name_prefix}-*",
    "/aws/apigateway/${var.name_prefix}-*",
    "/aws/vendedlogs/${var.name_prefix}-*",
    "aws-waf-logs-${var.name_prefix}-*",
  ]
}

# Domain keys: data, logs, ai (EN-14). The service grants whose producers live in the platform stack are driven by
# inputs that stay empty at the first apply (CloudFront distributions, GuardDuty Malware Protection roles): foundation
# is applied again once platform exists. CloudTrail, Config and log delivery to S3 are off: the baseline services
# already exist in the workshop account and are not managed here.
module "kms_keys" {
  source = "../../modules/kms-keys"

  name_prefix                 = var.name_prefix
  environment                 = var.env
  admin_principal_arns        = var.admin_principal_arns
  kms_deletion_window_in_days = var.kms_deletion_window_in_days

  enable_cloudwatch_logs  = true
  log_group_name_patterns = local.log_group_name_patterns

  cloudfront_distribution_arns           = var.cloudfront_distribution_arns
  guardduty_malware_protection_role_arns = var.guardduty_malware_protection_role_arns

  enable_bedrock = var.enable_bedrock

  enable_deletion_alerts = var.enable_deletion_alerts
  alert_topic_arn        = aws_sns_topic.alerts.arn
}

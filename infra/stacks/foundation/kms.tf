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

# Domain keys: data, logs, ai (EN-14) and edge. The edge key encrypts the SPA bucket only and carries the CloudFront
# grant scoped to the distributions of this account, so it exists before the distribution and the platform stack needs
# no second apply of foundation for CloudFront. The GuardDuty Malware Protection grant, whose producer lives in the
# platform stack, is driven by an input that stays empty at the first apply: foundation is applied again once platform
# exists. CloudTrail, Config and log delivery to S3 are off: the baseline services already exist in the workshop
# account and are not managed here.
module "kms_keys" {
  source = "../../modules/kms-keys"

  name_prefix                 = var.name_prefix
  environment                 = var.env
  admin_principal_arns        = var.admin_principal_arns
  kms_deletion_window_in_days = var.kms_deletion_window_in_days

  keys = {
    data = { description = "Encrypts application data at rest: DynamoDB tables, SQS queues, S3 buckets" }
    logs = { description = "Encrypts logs: CloudWatch Logs log groups, CloudTrail, AWS Config" }
    ai   = { description = "Encrypts the AI assistant data: Bedrock Knowledge Base sources and ingestion" }
    edge = { description = "Encrypts the SPA bucket served by CloudFront through its origin access control", edge = true }
  }

  enable_cloudwatch_logs  = true
  log_group_name_patterns = local.log_group_name_patterns

  guardduty_malware_protection_role_arns = var.guardduty_malware_protection_role_arns

  enable_bedrock = var.enable_bedrock

  enable_deletion_alerts = var.enable_deletion_alerts
  alert_topic_arn        = aws_sns_topic.alerts.arn
}

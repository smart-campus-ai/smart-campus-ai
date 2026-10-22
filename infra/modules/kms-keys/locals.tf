data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  partition        = data.aws_partition.current.partition
  region           = data.aws_region.current.region
  account_root_arn = "arn:${local.partition}:iam::${local.account_id}:root"

  # logs key. CloudWatch Logs puts the log group ARN in the encryption context: the key only works for log groups of this
  # account and region whose name matches a pattern.
  logs_service_principal = "logs.${local.region}.amazonaws.com"
  log_group_arn_patterns = [
    for pattern in concat(["${var.name_prefix}-*"], var.log_group_name_patterns) :
    "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${pattern}"
  ]
  cloudtrail_trail_arn_pattern = "arn:${local.partition}:cloudtrail:*:${local.account_id}:trail/*"
  config_service_linked_role   = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
  log_delivery_source_arn      = "arn:${local.partition}:logs:${local.region}:${local.account_id}:delivery-source:*"

  # ai key.
  bedrock_knowledge_base_arn = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:knowledge-base/*"

  # Services in the kms:ViaService condition, per domain.
  via_service_names = {
    data = [for s in sort(var.data_via_services) : "${s}.${local.region}.amazonaws.com"]
    ai   = [for s in sort(var.ai_via_services) : "${s}.${local.region}.amazonaws.com"]
  }

  # Usage actions delegated to IAM through the account root (same list as the state backend key).
  usage_actions = [
    "kms:Decrypt",
    "kms:DescribeKey",
    "kms:Encrypt",
    "kms:GenerateDataKey",
    "kms:GenerateDataKeyWithoutPlaintext",
    "kms:ReEncryptFrom",
    "kms:ReEncryptTo",
  ]

  aliases = { for domain in keys(var.keys) : domain => "alias/${var.name_prefix}-${domain}" }

  # Key protection alert: CloudTrail records the key identifier exactly as the caller wrote it (key ID, key ARN or alias).
  protected_key_identifiers = sort(flatten([
    for domain, key in aws_kms_key.this : [key.key_id, key.arn, local.aliases[domain]]
  ]))
}

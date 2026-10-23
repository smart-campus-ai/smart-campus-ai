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
  # The account is shared by the environments: trails and delivery sources must carry this environment's prefix.
  cloudtrail_trail_arn_pattern = "arn:${local.partition}:cloudtrail:*:${local.account_id}:trail/${var.name_prefix}-*"
  config_service_linked_role   = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
  log_delivery_source_arn      = "arn:${local.partition}:logs:${local.region}:${local.account_id}:delivery-source:${var.name_prefix}-*"

  # edge key. Distribution ARNs carry a generated ID: the grant covers the distributions of this account only. The key
  # is dedicated to buckets served by CloudFront, whose bucket policy pins the distribution (OAC).
  cloudfront_account_distribution_arn = "arn:${local.partition}:cloudfront::${local.account_id}:distribution/*"

  # ai key. Knowledge base ARNs carry a generated ID, not a name, so they cannot be scoped to name_prefix: the ai key
  # itself is per environment, and the grant stays limited to this account's knowledge bases.
  bedrock_knowledge_base_arn = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:knowledge-base/*"

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

  # Read-only actions delegated to IAM through the account root, so that CI roles can plan and apply (refresh) the keys.
  # TagResource is not here: it stays with the key administrators.
  read_actions = [
    "kms:GetKeyPolicy",
    "kms:GetKeyRotationStatus",
    "kms:ListResourceTags",
  ]

  aliases = { for domain in keys(var.keys) : domain => "alias/${var.name_prefix}-${domain}" }

  # Key protection alert: CloudTrail records the key identifier exactly as the caller wrote it (key ID, key ARN or alias).
  protected_key_identifiers = sort(flatten([
    for domain, key in aws_kms_key.this : [key.key_id, key.arn, local.aliases[domain]]
  ]))

  # DeleteAlias carries the alias name, not a key identifier, in its request parameters.
  protected_alias_names = sort(values(local.aliases))
}

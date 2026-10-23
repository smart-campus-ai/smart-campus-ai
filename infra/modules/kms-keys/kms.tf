# Key policies: explicit principals only, never an unconditioned "*".
#
# Every key gets the same three base statements as the state backend key:
# - EnableIamDelegation: the account root principal. This is what delegates to IAM: a principal of the account uses the
#   key (usage actions) or reads it (describe, policy, rotation status, tags) only if its own IAM policy allows it. IAM
#   policies are the least-privilege control for usage, so there is no kms:ViaService statement on top: it would be
#   redundant with this one. Read-only actions let the CI plan and apply roles refresh the keys through IAM.
# - RootLockoutRecovery: PutKeyPolicy only, kept by the account root to recover from a lockout (AWS guidance). It
#   excludes ScheduleKeyDeletion and DisableKey, which stay reserved to the key administrators. Because any IAM
#   principal allowed kms:PutKeyPolicy could rewrite the policy through it, the alert rule watches PutKeyPolicy.
# - KeyAdministration: the named admin principals, the only way to administer the keys.
#
# Service grants come on top, each one enabled by an input, each one conditioned (encryption context, aws:SourceArn,
# aws:SourceAccount, kms:ViaService, kms:CallerAccount) so that a service can only act for this account's resources.
#
# Resources are "*" because, in a key policy, "*" means "this key" (no resource-level scoping exists there).
data "aws_iam_policy_document" "key" {
  # checkov:skip=CKV_AWS_111: Key policy: Resource "*" means this key only; write access is limited to named admin principals.
  # checkov:skip=CKV_AWS_356: Key policy: Resource "*" is the only valid value and refers to the key itself.
  # checkov:skip=CKV_AWS_109: Key policy: PutKeyPolicy is limited to the admin principals and the account root (AWS lockout guidance).
  for_each = var.keys

  statement {
    sid       = "EnableIamDelegation"
    effect    = "Allow"
    resources = ["*"]
    actions   = concat(local.usage_actions, local.read_actions)

    principals {
      type        = "AWS"
      identifiers = [local.account_root_arn]
    }
  }

  statement {
    sid       = "RootLockoutRecovery"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["kms:PutKeyPolicy"]

    principals {
      type        = "AWS"
      identifiers = [local.account_root_arn]
    }
  }

  statement {
    sid       = "KeyAdministration"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:CancelKeyDeletion",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:DescribeKey",
      "kms:DisableKey",
      "kms:DisableKeyRotation",
      "kms:EnableKey",
      "kms:EnableKeyRotation",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateAlias",
    ]

    principals {
      type        = "AWS"
      identifiers = var.admin_principal_arns
    }
  }

  # ---- logs key ----------------------------------------------------------------------------------------------------

  # CloudWatch Logs: only for log groups of this account and region whose name matches the patterns.
  dynamic "statement" {
    for_each = each.key == "logs" && var.enable_cloudwatch_logs ? [1] : []

    content {
      sid       = "AllowCloudWatchLogs"
      effect    = "Allow"
      resources = ["*"]

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
        "kms:ReEncrypt*",
      ]

      principals {
        type        = "Service"
        identifiers = [local.logs_service_principal]
      }

      condition {
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = local.log_group_arn_patterns
      }
    }
  }

  # CloudTrail: encrypt log files of trails of this account (encryption context + source account).
  dynamic "statement" {
    for_each = each.key == "logs" && var.enable_cloudtrail ? [1] : []

    content {
      sid       = "AllowCloudTrailEncrypt"
      effect    = "Allow"
      resources = ["*"]
      actions   = ["kms:GenerateDataKey*"]

      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }

      condition {
        test     = "StringLike"
        variable = "kms:EncryptionContext:aws:cloudtrail:arn"
        values   = [local.cloudtrail_trail_arn_pattern]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }

  dynamic "statement" {
    for_each = each.key == "logs" && var.enable_cloudtrail ? [1] : []

    content {
      sid       = "AllowCloudTrailDescribeKey"
      effect    = "Allow"
      resources = ["*"]
      actions   = ["kms:DescribeKey"]

      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }

  # AWS Config: the service-linked role delivers configuration snapshots to the encrypted S3 bucket.
  dynamic "statement" {
    for_each = each.key == "logs" && var.enable_config ? [1] : []

    content {
      sid       = "AllowConfigServiceLinkedRole"
      effect    = "Allow"
      resources = ["*"]

      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
      ]

      principals {
        type        = "AWS"
        identifiers = [local.config_service_linked_role]
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "kms:CallerAccount"
        values   = [local.account_id]
      }
    }
  }

  # Vended logs delivery (WAF, API Gateway logs sent to S3): delivery sources of this account only.
  dynamic "statement" {
    for_each = each.key == "logs" && var.enable_log_delivery ? [1] : []

    content {
      sid       = "AllowLogDelivery"
      effect    = "Allow"
      resources = ["*"]

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
        "kms:ReEncrypt*",
      ]

      principals {
        type        = "Service"
        identifiers = ["delivery.logs.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = [local.log_delivery_source_arn]
      }
    }
  }

  # ---- data key ----------------------------------------------------------------------------------------------------

  # CloudFront origin access control on SSE-KMS buckets: named distributions only.
  dynamic "statement" {
    for_each = each.key == "data" && length(var.cloudfront_distribution_arns) > 0 ? [1] : []

    content {
      sid       = "AllowCloudFrontOriginAccessControl"
      effect    = "Allow"
      resources = ["*"]

      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey*",
      ]

      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = var.cloudfront_distribution_arns
      }
    }
  }

  # GuardDuty Malware Protection for S3: the named scan roles, only through S3.
  dynamic "statement" {
    for_each = each.key == "data" && length(var.guardduty_malware_protection_role_arns) > 0 ? [1] : []

    content {
      sid       = "AllowGuardDutyMalwareProtection"
      effect    = "Allow"
      resources = ["*"]

      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey*",
      ]

      principals {
        type        = "AWS"
        identifiers = var.guardduty_malware_protection_role_arns
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "kms:CallerAccount"
        values   = [local.account_id]
      }
    }
  }

  # ---- ai key ------------------------------------------------------------------------------------------------------

  # Bedrock: Knowledge Bases of this account only (confused deputy protection).
  dynamic "statement" {
    for_each = each.key == "ai" && var.enable_bedrock ? [1] : []

    content {
      sid       = "AllowBedrockKnowledgeBases"
      effect    = "Allow"
      resources = ["*"]

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey*",
      ]

      principals {
        type        = "Service"
        identifiers = ["bedrock.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = [local.bedrock_knowledge_base_arn]
      }
    }
  }

}

resource "aws_kms_key" "this" {
  for_each = var.keys

  description              = each.value.description
  deletion_window_in_days  = var.kms_deletion_window_in_days
  enable_key_rotation      = true
  rotation_period_in_days  = 365
  is_enabled               = true
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  policy                   = data.aws_iam_policy_document.key[each.key].json

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-${each.key}"
    Environment = var.environment
  })

  lifecycle {
    precondition {
      condition     = var.environment != "prod" || var.kms_deletion_window_in_days >= 30
      error_message = "kms_deletion_window_in_days must be 30 when environment is \"prod\": a deleted key makes its data unreadable."
    }
  }
}

resource "aws_kms_alias" "this" {
  for_each = var.keys

  name          = local.aliases[each.key]
  target_key_id = aws_kms_key.this[each.key].key_id
}

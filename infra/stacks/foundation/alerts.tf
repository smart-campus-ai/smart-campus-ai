locals {
  # Services that publish to the alerts topic and therefore need the alerts key (SNS encrypts with the publisher's
  # permissions): EventBridge (key protection rule), CloudWatch (alarms of the platform stack) and, when the budget
  # exists, AWS Budgets and Cost Anomaly Detection.
  alert_publisher_services = concat(
    ["events.amazonaws.com", "cloudwatch.amazonaws.com"],
    var.enable_budget ? ["budgets.amazonaws.com", "costalerts.amazonaws.com"] : [],
  )

  alarm_arn_pattern = "arn:${local.partition}:cloudwatch:${var.aws_region}:${local.account_id}:alarm:${var.name_prefix}-*"
}

# Dedicated key for the alerts topic. The domain keys cannot be used: an SNS topic encrypted with a CMK only receives
# events from EventBridge, CloudWatch or Budgets if the key policy lets those service principals call
# kms:Decrypt / kms:GenerateDataKey, and the kms-keys module has no such grant. Without it the alerts would be dropped
# silently. The key policy follows the module's: IAM delegation through the account root, named administrators, one
# conditioned service statement.
data "aws_iam_policy_document" "alerts_key" {
  # checkov:skip=CKV_AWS_111: Key policy: Resource "*" means this key only; write access is limited to named admin principals.
  # checkov:skip=CKV_AWS_356: Key policy: Resource "*" is the only valid value and refers to the key itself.
  # checkov:skip=CKV_AWS_109: Key policy: PutKeyPolicy is limited to the admin principals and the account root (AWS lockout guidance).

  statement {
    sid       = "EnableIamDelegation"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
    ]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "RootLockoutRecovery"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["kms:PutKeyPolicy"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
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

  statement {
    sid       = "AllowAlertPublishers"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
    ]

    principals {
      type        = "Service"
      identifiers = local.alert_publisher_services
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_kms_key" "alerts" {
  description              = "Encrypts the ${var.name_prefix} ops alerts SNS topic"
  deletion_window_in_days  = var.kms_deletion_window_in_days
  enable_key_rotation      = true
  rotation_period_in_days  = 365
  is_enabled               = true
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  policy                   = data.aws_iam_policy_document.alerts_key.json

  tags = {
    Name = "${var.name_prefix}-alerts"
  }
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/${var.name_prefix}-alerts"
  target_key_id = aws_kms_key.alerts.key_id
}

# Ops alerts topic (key deletion alerts, budget, platform alarms). The notifications module of the platform stack owns
# the admins and ops topics of the application; this one is the infrastructure alert channel published to SSM.
# No subscription here: an email endpoint is PII and needs a manual confirmation, add it outside the repository.
resource "aws_sns_topic" "alerts" {
  name              = "${var.name_prefix}-alerts"
  kms_master_key_id = aws_kms_key.alerts.arn

  tags = {
    Name = "${var.name_prefix}-alerts"
  }
}

data "aws_iam_policy_document" "alerts_topic" {
  source_policy_documents = [for b in module.budget : b.topic_policy_statement_json]

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sns:*"]
    resources = [aws_sns_topic.alerts.arn]

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

  # Only the key protection rule of this environment may publish as EventBridge.
  dynamic "statement" {
    for_each = var.enable_deletion_alerts ? [1] : []

    content {
      sid       = "AllowKeyProtectionRule"
      effect    = "Allow"
      actions   = ["sns:Publish"]
      resources = [aws_sns_topic.alerts.arn]

      principals {
        type        = "Service"
        identifiers = ["events.amazonaws.com"]
      }

      condition {
        test     = "ArnEquals"
        variable = "aws:SourceArn"
        values   = [module.kms_keys.deletion_alert_rule_arn]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }

  # CloudWatch alarms of this environment (platform stack): alarm names carry the environment prefix.
  statement {
    sid       = "AllowEnvironmentAlarms"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.alarm_arn_pattern]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}

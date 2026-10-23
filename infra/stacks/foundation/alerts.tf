locals {
  # Services that publish to the alerts topic and therefore need the alerts key (SNS encrypts with the publisher's
  # permissions): EventBridge (key protection rule), CloudWatch (alarms of the platform stack) and, when the budget
  # exists, AWS Budgets and Cost Anomaly Detection.
  alert_publisher_services = concat(
    ["events.amazonaws.com", "cloudwatch.amazonaws.com"],
    var.enable_budget ? ["budgets.amazonaws.com", "costalerts.amazonaws.com"] : [],
  )

  alarm_arn_pattern = "arn:${local.partition}:cloudwatch:${var.aws_region}:${local.account_id}:alarm:${var.name_prefix}-*"

  # Known before the topic exists: the alerts key policy pins SNS encryption to this topic without a dependency cycle
  # (the topic references the key). A postcondition on the topic checks that the two stay equal.
  alerts_topic_name = "${var.name_prefix}-alerts"
  alerts_topic_arn  = "arn:${local.partition}:sns:${var.aws_region}:${local.account_id}:${local.alerts_topic_name}"
  alerts_key_alias  = "alias/${var.name_prefix}-alerts"
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

    # SNS puts the topic ARN in the encryption context: the publishers can only use this key for the alerts topic of
    # this environment, not for any other rule, alarm or budget of the account.
    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:sns:topicArn"
      values   = [local.alerts_topic_arn]
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

  lifecycle {
    precondition {
      condition     = alltrue([for arn in var.admin_principal_arns : strcontains(arn, ":${local.account_id}:")])
      error_message = "Every admin_principal_arns entry must belong to this account (${local.account_id}): a foreign principal would administer the alerts key."
    }

    precondition {
      condition     = alltrue([for arn in var.guardduty_malware_protection_role_arns : strcontains(arn, ":${local.account_id}:")])
      error_message = "Every guardduty_malware_protection_role_arns entry must belong to this account (${local.account_id}): the data key grant would open to a foreign role."
    }
  }
}

resource "aws_kms_alias" "alerts" {
  name          = local.alerts_key_alias
  target_key_id = aws_kms_key.alerts.key_id
}

# The alerts key is not covered by the kms-keys key protection rule (it only lists the domain keys), yet disabling it,
# rewriting its policy or scheduling its deletion would drop every alert, including those of the domain keys. This rule
# mirrors the module's for the alerts key and alias. Limit: once the key is disabled or pending deletion, SNS can no
# longer encrypt the message, so the alert for DisableKey and ScheduleKeyDeletion itself may not reach the subscribers;
# the failure is visible on the FailedInvocations metric of the rule. PutKeyPolicy and DisableKeyRotation do get through.
resource "aws_cloudwatch_event_rule" "alerts_key_protection" {
  count = var.enable_deletion_alerts ? 1 : 0

  name        = "${var.name_prefix}-alerts-key-protection"
  description = "Key deletion, disabling, rotation, policy or alias change on the ${var.name_prefix} alerts key"

  event_pattern = jsonencode({
    source      = ["aws.kms"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["kms.amazonaws.com"]
      "$or" = [
        {
          eventName = ["DisableKey", "DisableKeyRotation", "PutKeyPolicy", "ScheduleKeyDeletion"]
          requestParameters = {
            keyId = sort([aws_kms_key.alerts.key_id, aws_kms_key.alerts.arn, local.alerts_key_alias])
          }
        },
        {
          eventName = ["DeleteAlias"]
          requestParameters = {
            aliasName = [local.alerts_key_alias]
          }
        },
      ]
    }
  })

  tags = {
    Name = "${var.name_prefix}-alerts-key-protection"
  }
}

resource "aws_cloudwatch_event_target" "alerts_key_protection" {
  count = var.enable_deletion_alerts ? 1 : 0

  rule      = aws_cloudwatch_event_rule.alerts_key_protection[0].name
  target_id = "sns-alerts"
  arn       = aws_sns_topic.alerts.arn
}

# Ops alerts topic (key deletion alerts, budget, platform alarms). The notifications module of the platform stack owns
# the admins and ops topics of the application; this one is the infrastructure alert channel published to SSM.
# No subscription here: an email endpoint is PII and needs a manual confirmation, add it outside the repository.
resource "aws_sns_topic" "alerts" {
  name              = local.alerts_topic_name
  kms_master_key_id = aws_kms_key.alerts.arn

  tags = {
    Name = "${var.name_prefix}-alerts"
  }

  lifecycle {
    postcondition {
      condition     = self.arn == local.alerts_topic_arn
      error_message = "The alerts topic ARN differs from the one pinned in the alerts key policy (local.alerts_topic_arn)."
    }
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

  # Only the key protection rules of this environment (domain keys, alerts key) may publish as EventBridge.
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
        values   = [module.kms_keys.deletion_alert_rule_arn, aws_cloudwatch_event_rule.alerts_key_protection[0].arn]
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

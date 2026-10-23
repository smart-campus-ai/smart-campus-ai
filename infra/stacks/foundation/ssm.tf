# Contract foundation -> platform: SSM parameters under /smartcampus/<env>/foundation/ (no terraform_remote_state).
# Names are consumed by stacks/platform: do not rename them without changing the consumer.

locals {
  ssm_prefix = "/smartcampus/${var.env}/foundation"

  kms_domains = toset(["data", "logs", "ai", "edge"])
}

resource "aws_ssm_parameter" "kms_key_arn" {
  # checkov:skip=CKV2_AWS_34: The value is a KMS key ARN, not a secret; the platform stack reads it as a plain String.
  for_each = local.kms_domains

  name        = "${local.ssm_prefix}/kms/${each.key}/arn"
  description = "ARN of the ${each.key} KMS key of ${var.name_prefix}"
  type        = "String"
  value       = module.kms_keys.key_arns[each.key]

  tags = {
    Name = "${var.name_prefix}-kms-${each.key}-arn"
  }
}

resource "aws_ssm_parameter" "alerts_topic_arn" {
  # checkov:skip=CKV2_AWS_34: The value is an SNS topic ARN, not a secret; the platform stack reads it as a plain String.
  name        = "${local.ssm_prefix}/alerts/topic-arn"
  description = "ARN of the ${var.name_prefix} ops alerts SNS topic"
  type        = "String"
  value       = aws_sns_topic.alerts.arn

  tags = {
    Name = "${var.name_prefix}-alerts-topic-arn"
  }
}

resource "aws_ssm_parameter" "budget_arn" {
  # checkov:skip=CKV2_AWS_34: The value is a budget ARN, not a secret; published only when the budget is enabled.
  count = var.enable_budget ? 1 : 0

  name        = "${local.ssm_prefix}/budget_arn"
  description = "ARN of the ${var.name_prefix} monthly budget"
  type        = "String"
  value       = module.budget[0].budget_arn

  tags = {
    Name = "${var.name_prefix}-budget-arn"
  }
}

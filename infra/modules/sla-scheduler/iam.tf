# Execution role assumed by EventBridge Scheduler when a schedule of the SLA group fires. Confused deputy protection:
# only the scheduler service, acting for this account and for this schedule group, can assume it.
data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "AssumeBySchedulerForSlaGroup"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.group_arn]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name                 = local.role_name
  description          = "Assumed by EventBridge Scheduler to invoke the live alias of the escalation function (SLA schedules)."
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(var.tags, { Name = local.role_name })
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    sid       = "InvokeEscalationLiveAlias"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [var.escalation_alias_arn]
  }

  dynamic "statement" {
    for_each = var.enable_dlq ? [1] : []

    content {
      sid       = "SendFailedEventsToDlq"
      effect    = "Allow"
      actions   = ["sqs:SendMessage"]
      resources = [aws_sqs_queue.dlq[0].arn]
    }
  }

  # The queue is encrypted with a customer-managed key: the sender needs GenerateDataKey (and Decrypt) on it, only
  # through SQS.
  dynamic "statement" {
    for_each = var.enable_dlq ? [1] : []

    content {
      sid       = "UseDlqKey"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [var.dlq_kms_key_arn]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["sqs.${local.region}.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "${local.role_name}-invoke"
  role   = aws_iam_role.scheduler.name
  policy = data.aws_iam_policy_document.scheduler.json
}

# Not attached here: the tickets function role is owned by its lambda-service instance, which receives this document
# as an extra policy. It lets tickets manage schedules in the SLA group only and pass the execution role to the
# scheduler only (AC3).
data "aws_iam_policy_document" "tickets_schedules" {
  statement {
    sid       = "ManageSlaSchedules"
    effect    = "Allow"
    actions   = ["scheduler:CreateSchedule", "scheduler:DeleteSchedule"]
    resources = [local.schedules_arn]
  }

  statement {
    sid       = "PassSchedulerRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.scheduler.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_scheduler_schedule_group" "sla" {
  name = local.group_name

  tags = merge(var.tags, { Name = local.group_name })
}

# Dead-letter queue of the schedule targets. The schedules are created at runtime by the tickets function, which sets
# this queue as the target dead_letter_config (see the dlq_arn output).
resource "aws_sqs_queue" "dlq" {
  count = var.enable_dlq ? 1 : 0

  name                      = local.dlq_name
  kms_master_key_id         = var.dlq_kms_key_arn
  message_retention_seconds = var.dlq_message_retention_seconds

  tags = merge(var.tags, { Name = local.dlq_name })
}

data "aws_iam_policy_document" "dlq" {
  count = var.enable_dlq ? 1 : 0

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.dlq[0].arn]

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
}

resource "aws_sqs_queue_policy" "dlq" {
  count = var.enable_dlq ? 1 : 0

  queue_url = aws_sqs_queue.dlq[0].url
  policy    = data.aws_iam_policy_document.dlq[0].json
}

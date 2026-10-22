resource "aws_sqs_queue" "dlq" {
  # checkov:skip=CKV2_AWS_73: The dead-letter queue is the end of the failure path; it has no dead-letter queue of its own (alarm on its depth instead).
  count = var.enable_dlq ? 1 : 0

  name                      = local.dlq_name
  kms_master_key_id         = var.dlq_kms_key_arn
  message_retention_seconds = var.dlq_message_retention_seconds

  tags = local.tags
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

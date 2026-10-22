# Daily aggregates (per day, status and category; resolution time sums). The items hold counters
# only: no student identifier is ever stored here.
resource "aws_dynamodb_table" "this" {
  # checkov:skip=CKV2_AWS_16: On-demand billing has no capacity to scale; Auto Scaling does not apply.
  name         = local.name
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = var.partition_key_name
  range_key = var.sort_key_name

  deletion_protection_enabled = var.enable_deletion_protection

  attribute {
    name = var.partition_key_name
    type = "S"
  }

  attribute {
    name = var.sort_key_name
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = merge(var.tags, { Name = local.name })
}

# Failure destination of the stream mapping: batches that still fail after the retries.
resource "aws_sqs_queue" "dlq" {
  name                      = local.dlq_name
  kms_master_key_id         = var.kms_key_arn
  message_retention_seconds = var.dlq_retention_seconds

  tags = merge(var.tags, { Name = local.dlq_name })
}

data "aws_iam_policy_document" "dlq_tls" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:PurgeQueue",
      "sqs:ReceiveMessage",
      "sqs:SendMessage",
    ]
    resources = [aws_sqs_queue.dlq.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.url
  policy    = data.aws_iam_policy_document.dlq_tls.json
}

# tickets stream -> kpi-aggregator. The function_name must reference the :live alias
# so that the mapping targets the live alias.
resource "aws_lambda_event_source_mapping" "this" {
  event_source_arn  = var.stream_arn
  function_name     = var.function_name
  starting_position = var.starting_position

  batch_size                         = var.batch_size
  maximum_batching_window_in_seconds = var.maximum_batching_window_in_seconds
  maximum_retry_attempts             = var.maximum_retry_attempts
  maximum_record_age_in_seconds      = var.maximum_record_age_in_seconds

  # The function returns the failed sequence numbers; on a whole-batch error the batch is split.
  function_response_types        = ["ReportBatchItemFailures"]
  bisect_batch_on_function_error = true

  filter_criteria {
    filter {
      pattern = local.creation_pattern
    }

    filter {
      pattern = local.status_change_pattern
    }
  }

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.dlq.arn
    }
  }

  tags = merge(var.tags, { Name = "${local.name}-aggregator" })
}

# tickets stream -> notifier (US09). The mapping lives in the stack: neither lambda-service nor the kpi module can host
# it (the kpi mapping and its filter are specific to the aggregator).
#
# Event filter (OR of the two patterns), same ticket item selection as the kpi-aggregator: only the ticket item (sort
# key META) matters, the EVENT#<ts> audit items and TTL removals never wake up the notifier.
#   - new ticket: INSERT of the ticket item;
#   - status change candidate: MODIFY of the ticket item where both images carry a status.
#
# LIMITATION: a DynamoDB stream filter cannot express "OldImage.status != NewImage.status". The handler must compare the
# two statuses and ignore MODIFY records where the status did not change (US09-AC4), and report failed records through
# batchItemFailures (US09-AC5). The key names below are the defaults of the tickets-store and kpi modules.
locals {
  notifier_ticket_keys = { sk = { S = ["META"] } }

  notifier_filter_patterns = [
    jsonencode({
      eventName = ["INSERT"]
      dynamodb  = { Keys = local.notifier_ticket_keys }
    }),
    jsonencode({
      eventName = ["MODIFY"]
      dynamodb = {
        Keys     = local.notifier_ticket_keys
        OldImage = { status = { S = [{ exists = true }] } }
        NewImage = { status = { S = [{ exists = true }] } }
      }
    }),
  ]
}

# Stream read for the notifier role. No read access to the tickets table itself. The "data" key is usable through
# DynamoDB only and for the ciphertexts of the tickets table (the stream), to decrypt the records.
data "aws_iam_policy_document" "notifier_stream" {
  statement {
    sid       = "TicketsStreamRead"
    effect    = "Allow"
    actions   = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator"]
    resources = [module.tickets_store.stream_arn]
  }

  statement {
    sid       = "UseDataKeyForTicketsStream"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [local.kms_key_arns["data"]]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["dynamodb.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:dynamodb:tableName"
      values   = [module.tickets_store.table_name]
    }
  }
}

# An inline policy of the stack, separate from the SES policy of extra_policy_json, so that the mapping below can
# explicitly wait for it (depends_on).
resource "aws_iam_role_policy" "notifier_stream" {
  name   = "${var.name_prefix}-notifier-stream"
  role   = module.notifier.role_name
  policy = data.aws_iam_policy_document.notifier_stream.json
}

# The on-failure destination is the encrypted dead-letter queue of the function (lambda-service, data key). The role
# already holds sqs:SendMessage on it and the key through SQS, so no other grant is needed. The records of a failed
# stream batch only carry the stream position and the keys, not the ticket content.
resource "aws_lambda_event_source_mapping" "notifier" {
  event_source_arn  = module.tickets_store.stream_arn
  function_name     = module.notifier.alias_arn
  starting_position = "TRIM_HORIZON"

  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  maximum_retry_attempts             = 3
  maximum_record_age_in_seconds      = 86400

  # The function returns the failed sequence numbers; on a whole-batch error the batch is split.
  function_response_types        = ["ReportBatchItemFailures"]
  bisect_batch_on_function_error = true

  filter_criteria {
    dynamic "filter" {
      for_each = local.notifier_filter_patterns

      content {
        pattern = filter.value
      }
    }
  }

  destination_config {
    on_failure {
      destination_arn = module.notifier.dlq_arn
    }
  }

  # The mapping validates the stream permissions when it is created: wait for the policy, so that no second apply is
  # needed.
  depends_on = [aws_iam_role_policy.notifier_stream]
}

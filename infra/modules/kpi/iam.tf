# Permissions of the kpi-aggregator function, to attach to the role created by lambda-service.
# Deliberately absent: any read access to the tickets table (only its stream is readable).
data "aws_iam_policy_document" "aggregator" {
  statement {
    sid       = "StreamRead"
    actions   = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator"]
    resources = [var.stream_arn]
  }

  statement {
    sid       = "KpiWrite"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.this.arn]
  }

  statement {
    sid       = "FailureDestination"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }

  # The "data" key is shared: each statement restricts its use to one service and to the ciphertexts of
  # this module (kpi table, tickets stream, failure queue), so the function cannot decrypt anything else.
  statement {
    sid       = "KmsUseDynamoDb"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["dynamodb.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:dynamodb:tableName"
      values   = [local.name, local.tickets_table_name]
    }
  }

  statement {
    sid       = "KmsUseSqs"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sqs.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:sqs:arn"
      values   = [aws_sqs_queue.dlq.arn]
    }
  }
}

resource "aws_iam_policy" "aggregator" {
  name        = "${local.name}-aggregator-access"
  description = "Stream read, kpi table write and failure destination for the kpi-aggregator function."
  policy      = data.aws_iam_policy_document.aggregator.json

  tags = var.tags
}

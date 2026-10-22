resource "aws_dynamodb_table" "this" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  table_class  = "STANDARD"

  hash_key  = var.hash_key
  range_key = var.range_key

  dynamic "attribute" {
    for_each = local.attribute_types

    content {
      name = attribute.key
      type = attribute.value
    }
  }

  dynamic "global_secondary_index" {
    for_each = local.global_secondary_indexes

    content {
      name            = global_secondary_index.key
      hash_key        = global_secondary_index.value.hash_key
      range_key       = global_secondary_index.value.range_key
      projection_type = "ALL"
    }
  }

  # Purge of expired chat transcripts (US08). DynamoDB deletes expired items in the background, typically within
  # a few days after expiry; readers must therefore also filter on the TTL attribute.
  ttl {
    attribute_name = var.ttl_attribute_name
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  deletion_protection_enabled = var.deletion_protection_enabled

  stream_enabled   = var.enable_stream
  stream_view_type = var.enable_stream ? var.stream_view_type : null

  tags = merge(var.tags, { Name = local.table_name })
}

# Policy for the "chat" function role (EN-53-AC4): item access on this table and its indexes only. There is no
# Scan, no table administration and no wildcard; the caller attaches it to its own role.
data "aws_iam_policy_document" "access" {
  statement {
    sid    = "ChatSessionsItems"
    effect = "Allow"

    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:UpdateItem",
    ]

    resources = concat([aws_dynamodb_table.this.arn], local.index_arns)
  }
}

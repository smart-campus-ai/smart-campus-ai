resource "aws_dynamodb_table" "this" {
  # checkov:skip=CKV2_AWS_16: On-demand billing has no capacity to scale; Auto Scaling does not apply.
  name         = local.name
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = var.partition_key_name
  range_key = var.sort_key_name

  deletion_protection_enabled = var.enable_deletion_protection

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  dynamic "attribute" {
    for_each = local.key_attributes

    content {
      name = attribute.value
      type = "S"
    }
  }

  global_secondary_index {
    name            = local.owner_index_name
    hash_key        = var.owner_attribute_name
    range_key       = var.created_at_attribute_name
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = local.status_index_name
    hash_key        = var.status_attribute_name
    range_key       = var.created_at_attribute_name
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  dynamic "ttl" {
    for_each = var.ttl_attribute_name == null ? [] : [var.ttl_attribute_name]

    content {
      enabled        = true
      attribute_name = ttl.value
    }
  }

  tags = merge(var.tags, { Name = local.name })
}

resource "aws_dynamodb_contributor_insights" "this" {
  for_each = local.insights_targets

  table_name = aws_dynamodb_table.this.name
  index_name = each.value
}

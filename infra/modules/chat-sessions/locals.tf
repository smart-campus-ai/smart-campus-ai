locals {
  table_name = "${var.name_prefix}-chat-sessions"

  global_secondary_indexes = var.enable_owner_index ? {
    "by-owner" = {
      hash_key  = var.owner_index_hash_key
      range_key = var.owner_index_range_key
    }
  } : {}

  # Every attribute used by a key schema must be declared exactly once. Table keys come last so that they win on
  # a name shared with the owner index (the variable validations guarantee that the types then agree).
  attribute_types = merge(
    var.enable_owner_index ? {
      (var.owner_index_hash_key)  = "S"
      (var.owner_index_range_key) = "S"
    } : {},
    { (var.hash_key) = var.hash_key_type },
    var.range_key == null ? {} : { (var.range_key) = var.range_key_type },
  )

  index_arns = [for name in sort(keys(local.global_secondary_indexes)) : "${aws_dynamodb_table.this.arn}/index/${name}"]
}

mock_provider "aws" {
  # Computed attributes are unknown at plan time; the outputs build index ARNs from the table ARN.
  override_resource {
    target = aws_dynamodb_table.this
    values = {
      arn        = "arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-tickets"
      stream_arn = "arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-tickets/stream/2026-01-01T00:00:00.000"
    }
  }
}

variables {
  name_prefix                = "sc-dev"
  enable_deletion_protection = false

  # Documentation account ID and placeholder key ID.
  kms_key_arn = "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000"
}

# EN42-AC1: composite primary key and the two GSIs (owner + createdAt, status + createdAt)
run "en42_ac1_keys_and_gsis" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.name == "sc-dev-tickets"
    error_message = "The table name must be <name_prefix>-tickets."
  }

  assert {
    condition     = aws_dynamodb_table.this.hash_key == "pk" && aws_dynamodb_table.this.range_key == "sk"
    error_message = "The primary key must be composite (partition pk, sort sk)."
  }

  assert {
    condition     = toset([for a in aws_dynamodb_table.this.attribute : a.name]) == toset(["pk", "sk", "ownerSub", "status", "createdAt"]) && alltrue([for a in aws_dynamodb_table.this.attribute : a.type == "S"])
    error_message = "Exactly the key attributes must be declared, all as strings."
  }

  assert {
    condition     = length(aws_dynamodb_table.this.global_secondary_index) == 2
    error_message = "Exactly two global secondary indexes must exist."
  }

  assert {
    condition = (
      { for g in aws_dynamodb_table.this.global_secondary_index : g.name => g }["by-owner"].hash_key == "ownerSub" &&
      { for g in aws_dynamodb_table.this.global_secondary_index : g.name => g }["by-owner"].range_key == "createdAt"
    )
    error_message = "The owner GSI must be keyed by ownerSub + createdAt."
  }

  assert {
    condition = (
      { for g in aws_dynamodb_table.this.global_secondary_index : g.name => g }["by-status"].hash_key == "status" &&
      { for g in aws_dynamodb_table.this.global_secondary_index : g.name => g }["by-status"].range_key == "createdAt"
    )
    error_message = "The status GSI must be keyed by status + createdAt."
  }
}

# EN42-AC1: attribute names can be aligned with the SE contract
run "en42_ac1_key_names_configurable" {
  command = plan

  variables {
    partition_key_name        = "PK"
    sort_key_name             = "SK"
    owner_attribute_name      = "owner"
    status_attribute_name     = "ticketStatus"
    created_at_attribute_name = "created"
  }

  assert {
    condition     = aws_dynamodb_table.this.hash_key == "PK" && aws_dynamodb_table.this.range_key == "SK"
    error_message = "The primary key names must follow the variables."
  }

  assert {
    condition     = toset([for a in aws_dynamodb_table.this.attribute : a.name]) == toset(["PK", "SK", "owner", "ticketStatus", "created"])
    error_message = "The attribute definitions must follow the variables."
  }
}

# EN42-AC2: on-demand, PITR, CMK encryption
run "en42_ac2_mode_pitr_and_encryption" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.billing_mode == "PAY_PER_REQUEST"
    error_message = "The table must be on-demand."
  }

  assert {
    condition     = one(aws_dynamodb_table.this.point_in_time_recovery).enabled == true
    error_message = "Point-in-time recovery must be enabled."
  }

  assert {
    condition     = one(aws_dynamodb_table.this.server_side_encryption).enabled == true && one(aws_dynamodb_table.this.server_side_encryption).kms_key_arn == var.kms_key_arn
    error_message = "The table must be encrypted with the customer-managed key passed as input."
  }
}

# EN42-AC2: deletion protection is a per-environment decision
run "en42_ac2_deletion_protection_enabled_in_prod" {
  command = plan

  variables {
    name_prefix                = "sc-prod"
    enable_deletion_protection = true
  }

  assert {
    condition     = aws_dynamodb_table.this.deletion_protection_enabled == true
    error_message = "Deletion protection must follow enable_deletion_protection."
  }
}

run "en42_ac2_deletion_protection_disabled_in_dev" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.deletion_protection_enabled == false
    error_message = "Deletion protection must be off when enable_deletion_protection is false."
  }
}

# EN42-AC3: stream with new and old images
run "en42_ac3_stream_new_and_old_images" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.stream_enabled == true
    error_message = "The stream must be enabled."
  }

  assert {
    condition     = aws_dynamodb_table.this.stream_view_type == "NEW_AND_OLD_IMAGES"
    error_message = "The stream must expose new and old images."
  }
}

# EN42-AC4: outputs for the IAM policies of the functions
run "en42_ac4_outputs" {
  command = plan

  assert {
    condition     = output.table_name == "sc-dev-tickets"
    error_message = "table_name must expose the table name."
  }

  assert {
    condition     = output.table_arn == "arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-tickets"
    error_message = "table_arn must expose the table ARN."
  }

  assert {
    condition = output.index_arns == {
      "by-owner"  = "arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-tickets/index/by-owner"
      "by-status" = "arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-tickets/index/by-status"
    }
    error_message = "index_arns must expose one scoped ARN per GSI."
  }

  assert {
    condition     = output.stream_arn == "arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-tickets/stream/2026-01-01T00:00:00.000"
    error_message = "stream_arn must expose the stream ARN."
  }

  assert {
    condition     = output.owner_index_name == "by-owner" && output.status_index_name == "by-status"
    error_message = "The index names must be exposed."
  }
}

# EN42-AC5: TTL is optional
run "en42_ac5_ttl_disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_dynamodb_table.this.ttl) == 0
    error_message = "TTL must not be configured unless ttl_attribute_name is set."
  }
}

run "en42_ac5_ttl_enabled_when_attribute_set" {
  command = plan

  variables {
    ttl_attribute_name = "expiresAt"
  }

  assert {
    condition     = one(aws_dynamodb_table.this.ttl).enabled == true && one(aws_dynamodb_table.this.ttl).attribute_name == "expiresAt"
    error_message = "TTL must use the configured attribute."
  }
}

# EN42-AC6: Contributor Insights flag
run "en42_ac6_contributor_insights_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_dynamodb_contributor_insights.this) == 0
    error_message = "Contributor Insights must be off by default."
  }
}

run "en42_ac6_contributor_insights_on_table_and_indexes" {
  command = plan

  variables {
    enable_contributor_insights = true
  }

  assert {
    condition     = toset(keys(aws_dynamodb_contributor_insights.this)) == toset(["table", "by-owner", "by-status"])
    error_message = "Contributor Insights must cover the table and both indexes."
  }

  assert {
    condition     = aws_dynamodb_contributor_insights.this["table"].index_name == null
    error_message = "The table-level entry must not target an index."
  }

  assert {
    condition     = aws_dynamodb_contributor_insights.this["by-owner"].index_name == "by-owner"
    error_message = "The owner index entry must target by-owner."
  }
}

# Variable validations
run "en42_validation_name_prefix" {
  command = plan

  variables {
    name_prefix = "SC_Dev"
  }

  expect_failures = [var.name_prefix]
}

run "en42_validation_kms_key_arn_rejects_alias" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-3:123456789012:alias/sc-dev-data"
  }

  expect_failures = [var.kms_key_arn]
}

run "en42_validation_sort_key_differs_from_partition_key" {
  command = plan

  variables {
    sort_key_name = "pk"
  }

  expect_failures = [var.sort_key_name]
}

run "en42_validation_ttl_attribute_name" {
  command = plan

  variables {
    ttl_attribute_name = "1-bad name"
  }

  expect_failures = [var.ttl_attribute_name]
}

run "en42_validation_key_name_format" {
  command = plan

  variables {
    owner_attribute_name = "owner sub"
  }

  expect_failures = [var.owner_attribute_name]
}

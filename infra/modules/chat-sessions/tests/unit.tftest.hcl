mock_provider "aws" {
  # The table ARN is computed; the access policy resources and the index ARNs are built from it.
  override_resource {
    target = aws_dynamodb_table.this
    values = {
      arn        = "arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-chat-sessions"
      stream_arn = "arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-chat-sessions/stream/2026-01-01T00:00:00.000"
    }
  }

  # The invariants are asserted on the document arguments (known at plan), not on the JSON.
  override_data {
    target = data.aws_iam_policy_document.access
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix = "sc-dev"
  # Placeholder key of the documentation account.
  kms_key_arn = "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000"
}

# EN53-AC1: TTL is enabled on the default expiresAt attribute
run "en53_ac1_ttl_enabled_on_expires_at" {
  command = plan

  assert {
    condition     = one(aws_dynamodb_table.this.ttl).enabled == true
    error_message = "TTL must be enabled."
  }

  assert {
    condition     = one(aws_dynamodb_table.this.ttl).attribute_name == "expiresAt"
    error_message = "The default TTL attribute must be expiresAt."
  }
}

# EN53-AC1: the TTL attribute name is configurable
run "en53_ac1_ttl_attribute_configurable" {
  command = plan

  variables {
    ttl_attribute_name = "purgeAt"
  }

  assert {
    condition     = one(aws_dynamodb_table.this.ttl).enabled == true && one(aws_dynamodb_table.this.ttl).attribute_name == "purgeAt"
    error_message = "TTL must be enabled on the configured attribute."
  }
}

# EN53-AC1: retention is a documented variable exposed as an output
run "en53_ac1_retention_exposed" {
  command = plan

  variables {
    retention_days = 90
  }

  assert {
    condition     = output.retention_days == 90 && output.ttl_attribute_name == "expiresAt"
    error_message = "retention_days and the TTL attribute name must be exposed to the chat service."
  }
}

# EN53-AC1: rejects a TTL attribute that is a key of the table
run "en53_ac1_rejects_ttl_on_hash_key" {
  command = plan

  variables {
    ttl_attribute_name = "sessionId"
  }

  expect_failures = [var.ttl_attribute_name]
}

# EN53-AC1: rejects a TTL attribute that is the sort key
run "en53_ac1_rejects_ttl_on_range_key" {
  command = plan

  variables {
    ttl_attribute_name = "ts"
  }

  expect_failures = [var.ttl_attribute_name]
}

# EN53-AC1: rejects a retention outside 1 to 365 days
run "en53_ac1_rejects_retention_above_365" {
  command = plan

  variables {
    retention_days = 366
  }

  expect_failures = [var.retention_days]
}

# EN53-AC1: rejects a retention of zero days
run "en53_ac1_rejects_retention_zero" {
  command = plan

  variables {
    retention_days = 0
  }

  expect_failures = [var.retention_days]
}

# EN53-AC2: on-demand billing and name
run "en53_ac2_on_demand" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.billing_mode == "PAY_PER_REQUEST"
    error_message = "The table must be on-demand."
  }

  assert {
    condition     = aws_dynamodb_table.this.name == "sc-dev-chat-sessions"
    error_message = "The table name must be <prefix>-chat-sessions."
  }
}

# EN53-AC2: server-side encryption uses the given customer-managed key
run "en53_ac2_encrypted_with_data_key" {
  command = plan

  assert {
    condition     = one(aws_dynamodb_table.this.server_side_encryption).enabled == true
    error_message = "Server-side encryption must be enabled."
  }

  assert {
    condition     = one(aws_dynamodb_table.this.server_side_encryption).kms_key_arn == var.kms_key_arn
    error_message = "The table must be encrypted with the kms_key_arn input."
  }
}

# EN53-AC2: point-in-time recovery is enabled
run "en53_ac2_pitr_enabled" {
  command = plan

  assert {
    condition     = one(aws_dynamodb_table.this.point_in_time_recovery).enabled == true
    error_message = "Point-in-time recovery must be enabled."
  }
}

# EN53-AC2: deletion protection is on by default and configurable
run "en53_ac2_deletion_protection_default_on" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.deletion_protection_enabled == true
    error_message = "Deletion protection must be on by default."
  }
}

run "en53_ac2_deletion_protection_can_be_disabled" {
  command = plan

  variables {
    deletion_protection_enabled = false
  }

  assert {
    condition     = aws_dynamodb_table.this.deletion_protection_enabled == false
    error_message = "Deletion protection must follow the variable."
  }
}

# EN53-AC2: no stream by default
run "en53_ac2_no_stream_by_default" {
  command = plan

  assert {
    condition     = var.enable_stream == false
    error_message = "enable_stream must default to false."
  }

  assert {
    condition     = aws_dynamodb_table.this.stream_enabled == false
    error_message = "The table must not have a stream by default."
  }

  assert {
    condition     = output.stream_arn == null
    error_message = "stream_arn must be null when the stream is disabled."
  }
}

run "en53_ac2_stream_when_enabled" {
  command = plan

  variables {
    enable_stream    = true
    stream_view_type = "NEW_IMAGE"
  }

  assert {
    condition     = aws_dynamodb_table.this.stream_enabled == true && aws_dynamodb_table.this.stream_view_type == "NEW_IMAGE"
    error_message = "The stream must follow enable_stream and stream_view_type."
  }

  assert {
    condition     = output.stream_arn != null
    error_message = "stream_arn must be exposed when the stream is enabled."
  }
}

# EN53-AC2: extra tags are merged
run "en53_ac2_tags_merged" {
  command = plan

  variables {
    tags = { Component = "chat" }
  }

  assert {
    condition     = aws_dynamodb_table.this.tags["Component"] == "chat" && aws_dynamodb_table.this.tags["Name"] == "sc-dev-chat-sessions"
    error_message = "Extra tags must be merged with the Name tag."
  }
}

# EN53-AC2: rejects an alias ARN or a bare key ID
run "en53_ac2_rejects_kms_alias" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-3:123456789012:alias/sc-dev-data"
  }

  expect_failures = [var.kms_key_arn]
}

# EN53-AC2: rejects an invalid name_prefix
run "en53_ac2_rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Bad_Prefix"
  }

  expect_failures = [var.name_prefix]
}

# EN53-AC3: default keys are sessionId / ts
run "en53_ac3_default_key_schema" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.hash_key == "sessionId" && aws_dynamodb_table.this.range_key == "ts"
    error_message = "The default keys must be sessionId (partition) and ts (sort)."
  }

  assert {
    condition = alltrue([
      for a in aws_dynamodb_table.this.attribute : a.type == "S"
    ]) && length(aws_dynamodb_table.this.attribute) == 4
    error_message = "sessionId, ts, sub and createdAt must be declared once, as strings."
  }
}

# EN53-AC3: the by-owner index lists the sessions of a sub with a Query
run "en53_ac3_owner_index_by_sub" {
  command = plan

  assert {
    condition     = one([for g in aws_dynamodb_table.this.global_secondary_index : g if g.name == "by-owner"]).hash_key == "sub"
    error_message = "The by-owner index partition key must be the owner sub."
  }

  assert {
    condition     = one([for g in aws_dynamodb_table.this.global_secondary_index : g if g.name == "by-owner"]).range_key == "createdAt"
    error_message = "The by-owner index must be sorted by createdAt."
  }

  assert {
    condition     = output.owner_index_name == "by-owner" && length(output.index_arns) == 1
    error_message = "The owner index must be exposed."
  }
}

# EN53-AC3: the index is optional
run "en53_ac3_owner_index_disabled" {
  command = plan

  variables {
    enable_owner_index = false
  }

  assert {
    condition     = length(aws_dynamodb_table.this.global_secondary_index) == 0 && length(aws_dynamodb_table.this.attribute) == 2
    error_message = "No index and only the table keys must be declared when the owner index is disabled."
  }

  assert {
    condition     = output.owner_index_name == null && length(output.index_arns) == 0
    error_message = "No index must be exposed when the owner index is disabled."
  }
}

# EN53-AC3: keys are configurable, owner as partition key without sort key and without the index
run "en53_ac3_custom_keys_owner_partition" {
  command = plan

  variables {
    hash_key           = "sub"
    range_key          = "sessionTs"
    enable_owner_index = false
  }

  assert {
    condition     = aws_dynamodb_table.this.hash_key == "sub" && aws_dynamodb_table.this.range_key == "sessionTs"
    error_message = "The keys must follow the variables."
  }
}

# EN53-AC3: a table with a partition key only is allowed
run "en53_ac3_no_range_key" {
  command = plan

  variables {
    range_key = null
  }

  assert {
    condition     = aws_dynamodb_table.this.range_key == null && length(aws_dynamodb_table.this.attribute) == 3
    error_message = "A null range_key must produce a table without sort key."
  }
}

# EN53-AC3: the owner index may reuse a table key attribute declared once
run "en53_ac3_owner_index_reuses_key_attribute" {
  command = plan

  variables {
    hash_key              = "sub"
    owner_index_hash_key  = "sub"
    owner_index_range_key = "createdAt"
  }

  assert {
    condition     = length([for a in aws_dynamodb_table.this.attribute : a if a.name == "sub"]) == 1
    error_message = "A shared attribute must be declared once."
  }
}

# EN53-AC3: rejects an owner attribute that reuses a non-string key
run "en53_ac3_rejects_owner_key_type_clash" {
  command = plan

  variables {
    hash_key_type        = "N"
    owner_index_hash_key = "sessionId"
  }

  expect_failures = [var.owner_index_hash_key]
}

# EN53-AC3: rejects identical partition and sort keys
run "en53_ac3_rejects_same_hash_and_range_key" {
  command = plan

  variables {
    range_key = "sessionId"
  }

  expect_failures = [var.range_key]
}

# EN53-AC3: rejects an invalid key type
run "en53_ac3_rejects_invalid_key_type" {
  command = plan

  variables {
    hash_key_type = "X"
  }

  expect_failures = [var.hash_key_type]
}

# EN53-AC4: the access policy never allows Scan, administration or wildcards
run "en53_ac4_access_policy_least_privilege" {
  command = plan

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.access.statement :
      s.effect == "Allow" && !anytrue([for a in s.actions : a == "dynamodb:Scan" || a == "*" || a == "dynamodb:*" || endswith(a, "*")])
    ])
    error_message = "The access policy must be Allow-only, without Scan and without wildcard action."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.access.statement : contains(s.actions, "dynamodb:Query")
    ])
    error_message = "The access policy must allow Query."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.access.statement :
      !anytrue([for a in s.actions : contains(["dynamodb:CreateTable", "dynamodb:DeleteTable", "dynamodb:UpdateTable", "dynamodb:UpdateTimeToLive"], a)])
    ])
    error_message = "The access policy must not administer the table."
  }
}

# EN53-AC4: the access policy is scoped to this table and its indexes
run "en53_ac4_access_policy_scoped_to_table" {
  command = plan

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.access.statement :
      toset(s.resources) == toset([
        "arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-chat-sessions",
        "arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-chat-sessions/index/by-owner",
      ])
    ])
    error_message = "The access policy must only target the table and its by-owner index."
  }
}

# EN53-AC4: without index, the policy targets the table only
run "en53_ac4_access_policy_table_only_without_index" {
  command = plan

  variables {
    enable_owner_index = false
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.access.statement :
      toset(s.resources) == toset(["arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-chat-sessions"])
    ])
    error_message = "The access policy must only target the table when there is no index."
  }
}

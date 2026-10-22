mock_provider "aws" {
  # Computed attributes consumed by other resources, outputs and policies must be known at plan time.
  # Region is us-east-1 per ADR-0013 (KPI module deployed in us-east-1 for cross-region aggregation).
  override_resource {
    target = aws_dynamodb_table.this
    values = {
      arn = "arn:aws:dynamodb:us-east-1:123456789012:table/sc-dev-kpi"
    }
  }

  override_resource {
    target = aws_sqs_queue.dlq
    values = {
      arn = "arn:aws:sqs:us-east-1:123456789012:sc-dev-kpi-aggregator-dlq"
      url = "https://sqs.us-east-1.amazonaws.com/123456789012/sc-dev-kpi-aggregator-dlq"
      id  = "https://sqs.us-east-1.amazonaws.com/123456789012/sc-dev-kpi-aggregator-dlq"
    }
  }

  override_resource {
    target = aws_iam_policy.aggregator
    values = {
      arn = "arn:aws:iam::123456789012:policy/sc-dev-kpi-aggregator-access"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.aggregator
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.dlq_tls
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix                = "sc-dev"
  enable_deletion_protection = false

  # Documentation account ID and placeholder key ID.
  kms_key_arn   = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  stream_arn    = "arn:aws:dynamodb:us-east-1:123456789012:table/sc-dev-tickets/stream/2026-01-01T00:00:00.000"
  function_name = "sc-dev-kpi-aggregator:live"
}

# EN46-AC1: on-demand table, CMK encryption, PITR
run "en46_ac1_table_on_demand_with_pitr" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.name == "sc-dev-kpi"
    error_message = "The table name must be <name_prefix>-kpi."
  }

  assert {
    condition     = aws_dynamodb_table.this.billing_mode == "PAY_PER_REQUEST"
    error_message = "The table must be on-demand."
  }

  assert {
    condition     = aws_dynamodb_table.this.hash_key == "pk" && aws_dynamodb_table.this.range_key == "sk"
    error_message = "The primary key must be composite (partition pk, sort sk)."
  }

  assert {
    condition     = toset([for a in aws_dynamodb_table.this.attribute : a.name]) == toset(["pk", "sk"]) && alltrue([for a in aws_dynamodb_table.this.attribute : a.type == "S"])
    error_message = "Exactly the two key attributes must be declared, as strings."
  }

  assert {
    condition     = one(aws_dynamodb_table.this.point_in_time_recovery).enabled == true
    error_message = "Point-in-time recovery must be enabled."
  }
}

run "en46_ac1_table_encrypted_with_data_key" {
  command = plan

  assert {
    condition     = one(aws_dynamodb_table.this.server_side_encryption).enabled == true && one(aws_dynamodb_table.this.server_side_encryption).kms_key_arn == var.kms_key_arn
    error_message = "The table must be encrypted with the customer-managed key passed as input."
  }

  assert {
    condition     = aws_sqs_queue.dlq.kms_master_key_id == var.kms_key_arn
    error_message = "The failure queue must be encrypted with the customer-managed key passed as input."
  }
}

run "en46_ac1_deletion_protection_enabled_in_prod" {
  command = plan

  variables {
    name_prefix                = "sc-prod"
    enable_deletion_protection = true
  }

  assert {
    condition     = aws_dynamodb_table.this.deletion_protection_enabled == true && aws_dynamodb_table.this.name == "sc-prod-kpi"
    error_message = "Deletion protection must follow enable_deletion_protection."
  }
}

run "en46_ac1_deletion_protection_disabled_in_dev" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.deletion_protection_enabled == false
    error_message = "Deletion protection must be off when enable_deletion_protection is false."
  }
}

run "en46_ac1_key_names_configurable" {
  command = plan

  variables {
    partition_key_name = "day"
    sort_key_name      = "dimension"
  }

  assert {
    condition     = aws_dynamodb_table.this.hash_key == "day" && aws_dynamodb_table.this.range_key == "dimension"
    error_message = "The primary key names must follow the variables."
  }
}

# EN46-AC2: only creations and status changes pass the filter
run "en46_ac2_filter_creations_and_status_changes" {
  command = plan

  assert {
    condition     = length(one(aws_lambda_event_source_mapping.this.filter_criteria).filter) == 2
    error_message = "The mapping must carry exactly two filters (creation, status change)."
  }

  assert {
    condition = (
      length([for f in one(aws_lambda_event_source_mapping.this.filter_criteria).filter : f if jsondecode(f.pattern).eventName == ["INSERT"]]) == 1 &&
      length([for f in one(aws_lambda_event_source_mapping.this.filter_criteria).filter : f if jsondecode(f.pattern).eventName == ["MODIFY"]]) == 1
    )
    error_message = "Only INSERT and MODIFY events must pass; REMOVE events must be dropped."
  }

  assert {
    condition = alltrue([
      for f in one(aws_lambda_event_source_mapping.this.filter_criteria).filter :
      jsondecode(f.pattern).dynamodb.Keys.sk.S == ["META"]
    ])
    error_message = "Both filters must keep the ticket item (sort key META) only, not the audit trail items."
  }

  assert {
    condition = alltrue([
      for f in [for f in one(aws_lambda_event_source_mapping.this.filter_criteria).filter : f if jsondecode(f.pattern).eventName == ["MODIFY"]] :
      jsondecode(f.pattern).dynamodb.OldImage.status.S == [{ exists = true }] && jsondecode(f.pattern).dynamodb.NewImage.status.S == [{ exists = true }]
    ])
    error_message = "The MODIFY filter must require a status in both images."
  }
}

run "en46_ac2_filter_follows_ticket_contract" {
  command = plan

  variables {
    ticket_sort_key_name         = "SK"
    ticket_meta_sort_key_value   = "TICKET"
    ticket_status_attribute_name = "ticketStatus"
  }

  assert {
    condition = alltrue([
      for f in one(aws_lambda_event_source_mapping.this.filter_criteria).filter :
      jsondecode(f.pattern).dynamodb.Keys.SK.S == ["TICKET"]
    ])
    error_message = "The filter must follow the tickets key contract."
  }

  assert {
    condition = alltrue([
      for f in [for f in one(aws_lambda_event_source_mapping.this.filter_criteria).filter : f if jsondecode(f.pattern).eventName == ["MODIFY"]] :
      contains(keys(jsondecode(f.pattern).dynamodb.NewImage), "ticketStatus")
    ])
    error_message = "The MODIFY filter must follow the status attribute name."
  }
}

# EN46-AC3: robustness of the mapping
run "en46_ac3_partial_batch_response_and_bisect" {
  command = plan

  assert {
    condition     = aws_lambda_event_source_mapping.this.function_response_types == toset(["ReportBatchItemFailures"])
    error_message = "Batch item failure reporting must be enabled."
  }

  assert {
    condition     = aws_lambda_event_source_mapping.this.bisect_batch_on_function_error == true
    error_message = "Batches must be bisected on function error."
  }
}

run "en46_ac3_sqs_failure_destination" {
  command = plan

  assert {
    condition     = one(one(aws_lambda_event_source_mapping.this.destination_config).on_failure).destination_arn == "arn:aws:sqs:us-east-1:123456789012:sc-dev-kpi-aggregator-dlq"
    error_message = "The on-failure destination must be the module's SQS queue."
  }

  assert {
    condition     = aws_sqs_queue.dlq.name == "sc-dev-kpi-aggregator-dlq"
    error_message = "The failure queue name must be <name_prefix>-kpi-aggregator-dlq."
  }
}

run "en46_ac3_bounded_retries_and_age" {
  command = plan

  assert {
    condition     = aws_lambda_event_source_mapping.this.maximum_retry_attempts >= 0 && aws_lambda_event_source_mapping.this.maximum_record_age_in_seconds > 0
    error_message = "Retries and record age must be bounded so that failures reach the destination."
  }

  assert {
    condition     = aws_lambda_event_source_mapping.this.event_source_arn == var.stream_arn && aws_lambda_event_source_mapping.this.function_name == "sc-dev-kpi-aggregator:live"
    error_message = "The mapping must connect the tickets stream to the aggregator alias."
  }
}

run "en46_ac3_dlq_tls_only" {
  command = plan

  assert {
    condition     = length([for s in data.aws_iam_policy_document.dlq_tls.statement : s if s.effect == "Deny" && length(s.condition) == 1 && one(s.condition).variable == "aws:SecureTransport" && length(one(s.condition).values) == 1 && contains(one(s.condition).values, "false")]) == 1
    error_message = "The failure queue policy must deny requests that do not use TLS."
  }

  assert {
    condition     = alltrue([for s in data.aws_iam_policy_document.dlq_tls.statement : !anytrue([for a in s.actions : a == "*" || a == "sqs:*"])])
    error_message = "The failure queue policy must not use wildcard actions."
  }
}

# EN46-AC5: minimal rights of kpi-aggregator
run "en46_ac5_stream_read_and_kpi_write_only" {
  command = plan

  assert {
    condition     = { for s in data.aws_iam_policy_document.aggregator.statement : s.sid => s.resources }["StreamRead"] == toset([var.stream_arn])
    error_message = "Stream actions must be scoped to the tickets stream."
  }

  assert {
    condition     = { for s in data.aws_iam_policy_document.aggregator.statement : s.sid => s.actions }["StreamRead"] == toset(["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator"])
    error_message = "Stream access must be limited to reading the stream."
  }

  assert {
    condition     = { for s in data.aws_iam_policy_document.aggregator.statement : s.sid => s.resources }["KpiWrite"] == toset(["arn:aws:dynamodb:us-east-1:123456789012:table/sc-dev-kpi"])
    error_message = "Item actions must be scoped to the kpi table (no index, no other table)."
  }

  assert {
    condition     = { for s in data.aws_iam_policy_document.aggregator.statement : s.sid => s.actions }["KpiWrite"] == toset(["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"])
    error_message = "kpi access must be limited to item reads and writes by key."
  }

  assert {
    condition     = { for s in data.aws_iam_policy_document.aggregator.statement : s.sid => s.resources }["FailureDestination"] == toset(["arn:aws:sqs:us-east-1:123456789012:sc-dev-kpi-aggregator-dlq"])
    error_message = "SendMessage must be scoped to the failure queue."
  }

  assert {
    condition     = { for s in data.aws_iam_policy_document.aggregator.statement : s.sid => s.resources }["KmsUse"] == toset([var.kms_key_arn])
    error_message = "KMS actions must be scoped to the data key."
  }
}

run "en46_ac5_no_access_to_tickets_table" {
  command = plan

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.aggregator.statement :
      alltrue([for r in s.resources : !can(regex(":table/sc-dev-tickets($|/index/)", r))])
    ])
    error_message = "No statement may target the tickets table or its indexes (only its stream)."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.aggregator.statement :
      !anytrue([for a in s.actions : contains(["dynamodb:Query", "dynamodb:Scan", "dynamodb:BatchGetItem"], a)])
    ])
    error_message = "The aggregator must not be able to query or scan any table."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.aggregator.statement :
      alltrue([for a in s.actions : a != "*" && !endswith(a, ":*")]) && alltrue([for r in s.resources : r != "*"])
    ])
    error_message = "No wildcard action or resource is allowed."
  }
}

# EN46-AC5: the policy is exposed to be attached to the lambda-service role
run "en46_ac5_outputs" {
  command = plan

  assert {
    condition     = output.table_name == "sc-dev-kpi"
    error_message = "table_name must expose the table name."
  }

  assert {
    condition     = output.table_arn == "arn:aws:dynamodb:us-east-1:123456789012:table/sc-dev-kpi"
    error_message = "table_arn must expose the table ARN."
  }

  assert {
    condition     = output.aggregator_policy_arn == "arn:aws:iam::123456789012:policy/sc-dev-kpi-aggregator-access"
    error_message = "aggregator_policy_arn must expose the policy to attach to the aggregator role."
  }

  assert {
    condition     = output.dlq_arn == "arn:aws:sqs:us-east-1:123456789012:sc-dev-kpi-aggregator-dlq" && output.dlq_name == "sc-dev-kpi-aggregator-dlq"
    error_message = "The failure queue ARN and name must be exposed."
  }
}

# Variable validations
run "en46_validation_name_prefix" {
  command = plan

  variables {
    name_prefix = "SC_Dev"
  }

  expect_failures = [var.name_prefix]
}

run "en46_validation_kms_key_arn_rejects_alias" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:alias/sc-dev-data"
  }

  expect_failures = [var.kms_key_arn]
}

run "en46_validation_stream_arn_rejects_table_arn" {
  command = plan

  variables {
    stream_arn = "arn:aws:dynamodb:us-east-1:123456789012:table/sc-dev-tickets"
  }

  expect_failures = [var.stream_arn]
}

run "en46_validation_function_name_requires_live_alias" {
  command = plan

  variables {
    function_name = "sc-dev-kpi-aggregator"
  }

  expect_failures = [var.function_name]
}

run "en46_validation_function_name_rejects_version" {
  command = plan

  variables {
    function_name = "sc-dev-kpi-aggregator:1"
  }

  expect_failures = [var.function_name]
}

run "en46_validation_function_name_rejects_other_alias" {
  command = plan

  variables {
    function_name = "sc-dev-kpi-aggregator:prod"
  }

  expect_failures = [var.function_name]
}

run "en46_validation_function_name_accepts_live_alias_arn" {
  command = plan

  variables {
    function_name = "arn:aws:lambda:us-east-1:123456789012:function:sc-dev-kpi-aggregator:live"
  }

  # This should NOT fail - :live alias ARN is valid
}

run "en46_validation_function_name_rejects_invalid_format" {
  command = plan

  variables {
    function_name = "not a function"
  }

  expect_failures = [var.function_name]
}

run "en46_validation_sort_key_differs_from_partition_key" {
  command = plan

  variables {
    sort_key_name = "pk"
  }

  expect_failures = [var.sort_key_name]
}

run "en46_validation_starting_position" {
  command = plan

  variables {
    starting_position = "AT_TIMESTAMP"
  }

  expect_failures = [var.starting_position]
}

run "en46_validation_infinite_retries_refused" {
  command = plan

  variables {
    maximum_retry_attempts = -1
  }

  expect_failures = [var.maximum_retry_attempts]
}

run "en46_validation_unbounded_record_age_refused" {
  command = plan

  variables {
    maximum_record_age_in_seconds = -1
  }

  expect_failures = [var.maximum_record_age_in_seconds]
}

run "en46_validation_batch_size" {
  command = plan

  variables {
    batch_size = 0
  }

  expect_failures = [var.batch_size]
}

run "en46_validation_dlq_retention" {
  command = plan

  variables {
    dlq_retention_seconds = 30
  }

  expect_failures = [var.dlq_retention_seconds]
}

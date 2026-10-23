mock_provider "aws" {
  # Fake documentation account ID and region, used only to keep names and conditions predictable.
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "eu-west-3"
    }
  }

  # The mock returns random strings for computed attributes, which the IAM and SQS resources reject as invalid JSON.
  # The invariants are asserted on the document arguments (known at plan), not on the generated JSON.
  override_data {
    target = data.aws_iam_policy_document.assume
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.execution
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.dlq
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # Computed ARNs are unknown at plan time and consumed by the policies, the function and the outputs.
  override_resource {
    target = aws_iam_role.this
    values = {
      arn = "arn:aws:iam::123456789012:role/sc-dev-tickets-role"
      id  = "sc-dev-tickets-role"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.this
    values = {
      arn = "arn:aws:logs:eu-west-3:123456789012:log-group:/aws/lambda/sc-dev-tickets"
    }
  }

  override_resource {
    target = aws_sqs_queue.dlq
    values = {
      arn = "arn:aws:sqs:eu-west-3:123456789012:sc-dev-tickets-dlq"
      url = "https://sqs.eu-west-3.amazonaws.com/123456789012/sc-dev-tickets-dlq"
    }
  }

  override_resource {
    target = aws_lambda_function.this
    values = {
      arn           = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-tickets"
      version       = "1"
      qualified_arn = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-tickets:1"
    }
  }

  override_resource {
    target = aws_lambda_alias.live
    values = {
      arn        = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-tickets:live"
      invoke_arn = "arn:aws:apigateway:eu-west-3:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-tickets:live/invocations"
    }
  }
}

mock_provider "archive" {
  override_data {
    target = data.archive_file.placeholder
    values = {
      output_base64sha256 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    }
  }
}

variables {
  name_prefix   = "sc-dev"
  function_name = "tickets"
  runtime       = "python3.13"
  handler       = "app.handler"

  log_retention_in_days = 14

  # Documentation account ID and placeholder key and policy identifiers.
  logs_kms_key_arn         = "arn:aws:kms:eu-west-3:123456789012:key/11111111-1111-1111-1111-111111111111"
  environment_kms_key_arn  = "arn:aws:kms:eu-west-3:123456789012:key/33333333-3333-3333-3333-333333333333"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/sc-dev-boundary"
}

# EN-41-AC1: arm64 architecture and active tracing, no VPC
run "en41_ac1_arm64_and_active_tracing" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.architectures == tolist(["arm64"])
    error_message = "The function must run on arm64."
  }

  assert {
    condition     = one(aws_lambda_function.this.tracing_config).mode == "Active"
    error_message = "X-Ray tracing must be Active."
  }

  assert {
    condition     = aws_lambda_function.this.function_name == "sc-dev-tickets"
    error_message = "The function must be named <name_prefix>-<function_name>."
  }

  assert {
    condition     = aws_lambda_function.this.runtime == "python3.13" && aws_lambda_function.this.handler == "app.handler"
    error_message = "Runtime and handler must come from the variables."
  }

  assert {
    condition     = length(aws_lambda_function.this.vpc_config) == 0
    error_message = "The function must not be attached to a VPC (ADR)."
  }

  assert {
    condition     = aws_lambda_function.this.reserved_concurrent_executions == -1
    error_message = "Concurrency must stay unreserved by default."
  }
}

# EN-41-AC1: reserved concurrency is configurable
run "en41_ac1_reserved_concurrency_variable" {
  command = plan

  variables {
    reserved_concurrent_executions = 5
  }

  assert {
    condition     = aws_lambda_function.this.reserved_concurrent_executions == 5
    error_message = "reserved_concurrent_executions must be applied to the function."
  }
}

# EN-41-AC2: dedicated role carrying the permissions boundary, trust restricted by source account and function
run "en41_ac2_role_with_boundary_and_trust_conditions" {
  command = plan

  assert {
    condition     = aws_iam_role.this.name == "sc-dev-tickets-role"
    error_message = "The role must be named after the function."
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == "arn:aws:iam::123456789012:policy/sc-dev-boundary"
    error_message = "The role must carry the project permissions boundary."
  }

  assert {
    condition     = aws_lambda_function.this.role == aws_iam_role.this.arn
    error_message = "The function must use its own role."
  }

  assert {
    condition = alltrue([
      for statement in data.aws_iam_policy_document.assume.statement :
      contains([for p in statement.principals : p.type], "Service") && contains(flatten([for p in statement.principals : tolist(p.identifiers)]), "lambda.amazonaws.com")
    ])
    error_message = "The trust policy must only trust the Lambda service principal."
  }

  assert {
    condition = alltrue([
      for statement in data.aws_iam_policy_document.assume.statement :
      contains([for c in statement.condition : c.variable], "aws:SourceAccount") && contains([for c in statement.condition : c.variable], "aws:SourceArn")
    ])
    error_message = "The trust policy must carry aws:SourceAccount and aws:SourceArn conditions."
  }

  assert {
    condition = alltrue([
      for statement in data.aws_iam_policy_document.assume.statement :
      contains(flatten([for c in statement.condition : c.variable == "aws:SourceArn" ? tolist(c.values) : []]), "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-tickets")
    ])
    error_message = "aws:SourceArn must be the ARN of this function."
  }
}

# EN-41-AC2: each instance gets its own role (second instance with another function name)
run "en41_ac2_one_role_per_function" {
  command = plan

  variables {
    function_name = "kpi"
  }

  assert {
    condition     = aws_iam_role.this.name == "sc-dev-kpi-role" && aws_iam_role_policy.execution.name == "sc-dev-kpi-execution"
    error_message = "The role and its policy must be named after the function."
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == "arn:aws:iam::123456789012:policy/sc-dev-boundary"
    error_message = "Every instance must carry the permissions boundary."
  }
}

# EN-41-AC2: the policy is built from policy documents, scoped, without Action "*"
run "en41_ac2_policy_scoped_without_wildcard_action" {
  command = plan

  variables {
    extra_policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"ReadTickets\",\"Effect\":\"Allow\",\"Action\":[\"dynamodb:GetItem\"],\"Resource\":\"arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-tickets\"}]}"
  }

  assert {
    condition     = alltrue([for s in data.aws_iam_policy_document.execution.statement : s.actions == null ? false : !contains(s.actions, "*")])
    error_message = "No generated statement may use Action \"*\"."
  }

  assert {
    condition     = alltrue([for s in data.aws_iam_policy_document.execution.statement : s.sid == "XRay" ? true : !contains(s.resources, "*")])
    error_message = "Only the X-Ray statement may use Resource \"*\" (no resource-level support)."
  }

  assert {
    condition     = contains([for s in data.aws_iam_policy_document.execution.statement : s.sid], "WriteLogs") && contains([for s in data.aws_iam_policy_document.execution.statement : s.sid], "XRay")
    error_message = "The role must be able to write logs and X-Ray traces."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.execution.statement :
      s.sid != "WriteLogs" || (contains(s.resources, "arn:aws:logs:eu-west-3:123456789012:log-group:/aws/lambda/sc-dev-tickets:*") && !contains(s.actions, "logs:CreateLogGroup"))
    ])
    error_message = "Log permissions must be scoped to the function log group and must not allow CreateLogGroup."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.execution.source_policy_documents) == 1
    error_message = "The extra policy JSON must be merged into the execution policy."
  }

  assert {
    condition     = aws_iam_role_policy.execution.name == "sc-dev-tickets-execution"
    error_message = "The execution policy must be an inline policy of the role."
  }
}

# EN-41-AC2: without extra policy, nothing is merged
run "en41_ac2_no_extra_policy_by_default" {
  command = plan

  assert {
    condition     = length(data.aws_iam_policy_document.execution.source_policy_documents) == 0
    error_message = "No source policy document is expected without extra_policy_json."
  }
}

# EN-41-AC3: explicit log group, encrypted with the given key and retention
run "en41_ac3_log_group" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/lambda/sc-dev-tickets"
    error_message = "The log group must be /aws/lambda/<function name>."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:eu-west-3:123456789012:key/11111111-1111-1111-1111-111111111111"
    error_message = "The log group must be encrypted with the provided KMS key."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 14
    error_message = "The log group must use the provided retention."
  }

  assert {
    condition     = one(aws_lambda_function.this.logging_config).log_group == "/aws/lambda/sc-dev-tickets" && one(aws_lambda_function.this.logging_config).log_format == "JSON"
    error_message = "The function must log in JSON to the explicit log group."
  }
}

# EN-41-AC4: alias live, exposed as the integration output
run "en41_ac4_alias_live" {
  command = plan

  assert {
    condition     = aws_lambda_alias.live.name == "live"
    error_message = "The alias must be named live."
  }

  assert {
    condition     = aws_lambda_alias.live.function_name == "sc-dev-tickets"
    error_message = "The alias must target the function."
  }

  assert {
    condition     = aws_lambda_function.this.publish == true
    error_message = "A version must be published so the alias can follow it."
  }

  assert {
    condition     = output.alias_arn == aws_lambda_alias.live.arn && output.alias_name == "live"
    error_message = "The alias must be the output exposed for integrations."
  }

  assert {
    condition     = output.alias_invoke_arn == aws_lambda_alias.live.invoke_arn
    error_message = "The alias invoke ARN must be exposed for API Gateway."
  }
}

# EN-41-AC5: no DLQ by default
run "en41_ac5_no_dlq_by_default" {
  command = plan

  assert {
    condition     = length(aws_sqs_queue.dlq) == 0 && length(aws_lambda_function.this.dead_letter_config) == 0
    error_message = "No DLQ must be created unless enable_dlq is true."
  }

  assert {
    condition     = output.dlq_arn == null
    error_message = "dlq_arn must be null when enable_dlq is false."
  }
}

# EN-41-AC5: encrypted DLQ wired as dead-letter target, with a send permission and a TLS-only policy
run "en41_ac5_encrypted_dlq" {
  command = plan

  variables {
    enable_dlq      = true
    dlq_kms_key_arn = "arn:aws:kms:eu-west-3:123456789012:key/22222222-2222-2222-2222-222222222222"
  }

  assert {
    condition     = length(aws_sqs_queue.dlq) == 1 && aws_sqs_queue.dlq[0].name == "sc-dev-tickets-dlq"
    error_message = "A queue named <function>-dlq must be created."
  }

  assert {
    condition     = aws_sqs_queue.dlq[0].kms_master_key_id == "arn:aws:kms:eu-west-3:123456789012:key/22222222-2222-2222-2222-222222222222"
    error_message = "The DLQ must be encrypted with the provided customer-managed key."
  }

  assert {
    condition     = one(aws_lambda_function.this.dead_letter_config).target_arn == aws_sqs_queue.dlq[0].arn
    error_message = "The queue must receive the failed asynchronous invocations."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.execution.statement :
      s.sid == "SendToDlq" && contains(s.actions, "sqs:SendMessage") && contains(s.resources, "arn:aws:sqs:eu-west-3:123456789012:sc-dev-tickets-dlq")
    ])
    error_message = "The role must be allowed to send to the DLQ only."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.execution.statement :
      s.sid == "UseDlqKey" && contains(s.actions, "kms:GenerateDataKey") && contains(s.resources, "arn:aws:kms:eu-west-3:123456789012:key/22222222-2222-2222-2222-222222222222")
    ])
    error_message = "The role must be allowed to use the DLQ key."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.execution.statement :
      s.sid == "UseDlqKey" && anytrue([
        for c in s.condition :
        c.test == "StringEquals" && c.variable == "kms:ViaService" && contains(tolist(c.values), "sqs.eu-west-3.amazonaws.com")
      ])
    ])
    error_message = "The DLQ key must only be usable through SQS (kms:ViaService condition)."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.dlq[0].statement :
      s.effect == "Deny" && contains(flatten([for c in s.condition : c.variable]), "aws:SecureTransport")
    ])
    error_message = "The DLQ policy must deny non-TLS access."
  }

  assert {
    condition     = output.dlq_arn == "arn:aws:sqs:eu-west-3:123456789012:sc-dev-tickets-dlq"
    error_message = "dlq_arn must be exposed for the depth alarm."
  }
}

# EN-41-AC5: on-failure destination attached to the live alias, with the matching send permission
run "en41_ac5_on_failure_destination" {
  command = plan

  variables {
    on_failure_destination_arn = "arn:aws:sns:eu-west-3:123456789012:sc-dev-ops-alerts"
  }

  assert {
    condition     = length(aws_lambda_function_event_invoke_config.live) == 1
    error_message = "An asynchronous invoke configuration is expected."
  }

  assert {
    condition     = aws_lambda_function_event_invoke_config.live[0].qualifier == "live"
    error_message = "The on-failure destination must be attached to the live alias."
  }

  assert {
    condition     = one(one(aws_lambda_function_event_invoke_config.live[0].destination_config).on_failure).destination == "arn:aws:sns:eu-west-3:123456789012:sc-dev-ops-alerts"
    error_message = "The failure destination must be the provided ARN."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.execution.statement :
      s.sid == "SendToOnFailureDestination" && contains(s.actions, "sns:Publish") && contains(s.resources, "arn:aws:sns:eu-west-3:123456789012:sc-dev-ops-alerts")
    ])
    error_message = "The role must be allowed to publish to the destination only."
  }
}

# EN-41-AC5: no invoke configuration without destination
run "en41_ac5_no_destination_by_default" {
  command = plan

  assert {
    condition     = length(aws_lambda_function_event_invoke_config.live) == 0
    error_message = "No invoke configuration is expected without on_failure_destination_arn."
  }
}

# EN-41: environment variables and their optional customer-managed key
run "en41_environment_variables_and_kms" {
  command = plan

  variables {
    environment_variables = { TABLE_NAME = "sc-dev-tickets", SIGNING_KEY_SSM_PARAMETER = "/smartcampus/dev/platform/signing-key" }
  }

  assert {
    condition     = one(aws_lambda_function.this.environment).variables == tomap({ TABLE_NAME = "sc-dev-tickets", SIGNING_KEY_SSM_PARAMETER = "/smartcampus/dev/platform/signing-key" })
    error_message = "Environment variables must be passed to the function."
  }

  assert {
    condition     = aws_lambda_function.this.kms_key_arn == "arn:aws:kms:eu-west-3:123456789012:key/33333333-3333-3333-3333-333333333333"
    error_message = "Environment variables must be encrypted with the provided key."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.execution.statement :
      s.sid == "DecryptEnvironment" && contains(s.actions, "kms:Decrypt") && contains(s.resources, "arn:aws:kms:eu-west-3:123456789012:key/33333333-3333-3333-3333-333333333333")
    ])
    error_message = "The role must be allowed to decrypt the environment with the provided key."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.execution.statement :
      s.sid == "DecryptEnvironment" && anytrue([
        for c in s.condition :
        c.test == "StringEquals" && c.variable == "kms:EncryptionContext:aws:lambda:FunctionArn" && contains(tolist(c.values), "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-tickets")
      ])
    ])
    error_message = "The environment key must only be usable for this function (encryption context condition)."
  }
}

# EN-41: the environment key is always a customer-managed key, even without variables
run "en41_environment_key_always_applied" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.kms_key_arn == var.environment_kms_key_arn
    error_message = "The environment must always be encrypted with the customer-managed key."
  }

  assert {
    condition     = anytrue([for s in data.aws_iam_policy_document.execution.statement : s.sid == "DecryptEnvironment"])
    error_message = "The role must always be allowed to decrypt the environment key."
  }
}

run "en41_no_environment_block_when_empty" {
  command = plan

  assert {
    condition     = length(aws_lambda_function.this.environment) == 0
    error_message = "No environment block is expected without variables."
  }
}

# EN-41-AC7: validations
run "en41_ac7_retention_not_allowed" {
  command = plan

  variables {
    log_retention_in_days = 10
  }

  expect_failures = [var.log_retention_in_days]
}

run "en41_ac7_retention_never_expire_refused" {
  command = plan

  variables {
    log_retention_in_days = 0
  }

  expect_failures = [var.log_retention_in_days]
}

run "en41_ac7_empty_function_name" {
  command = plan

  variables {
    function_name = ""
  }

  expect_failures = [var.function_name]
}

run "en41_ac7_empty_name_prefix" {
  command = plan

  variables {
    name_prefix = ""
  }

  expect_failures = [var.name_prefix]
}

run "en41_ac7_invalid_runtime" {
  command = plan

  variables {
    runtime = "cobol"
  }

  expect_failures = [var.runtime]
}

run "en41_ac7_empty_handler" {
  command = plan

  variables {
    handler = ""
  }

  expect_failures = [var.handler]
}

run "en41_ac7_logs_key_must_be_a_key_arn" {
  command = plan

  variables {
    logs_kms_key_arn = "alias/sc-dev-logs"
  }

  expect_failures = [var.logs_kms_key_arn]
}

run "en41_ac7_permissions_boundary_must_be_a_policy_arn" {
  command = plan

  variables {
    permissions_boundary_arn = "sc-dev-boundary"
  }

  expect_failures = [var.permissions_boundary_arn]
}

run "en41_ac7_dlq_requires_a_key" {
  command = plan

  variables {
    enable_dlq = true
  }

  expect_failures = [var.dlq_kms_key_arn]
}

run "en41_ac7_extra_policy_wildcard_action_refused" {
  command = plan

  variables {
    extra_policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"*\",\"Resource\":\"arn:aws:s3:::sc-dev-bucket\"}]}"
  }

  expect_failures = [var.extra_policy_json]
}

run "en41_ac7_extra_policy_must_be_json" {
  command = plan

  variables {
    extra_policy_json = "not json"
  }

  expect_failures = [var.extra_policy_json]
}

run "en41_ac7_secret_environment_variable_refused" {
  command = plan

  variables {
    environment_variables = { DB_PASSWORD = "hunter2" }
  }

  expect_failures = [var.environment_variables]
}

run "en41_ac7_invalid_destination" {
  command = plan

  variables {
    on_failure_destination_arn = "arn:aws:s3:::sc-dev-bucket"
  }

  expect_failures = [var.on_failure_destination_arn]
}

run "en41_ac7_invalid_reserved_concurrency" {
  command = plan

  variables {
    reserved_concurrent_executions = -2
  }

  expect_failures = [var.reserved_concurrent_executions]
}

# EN-41-AC6: the code is owned by the pipeline. The first apply deploys the placeholder; when the placeholder hash
# changes afterwards, the code attributes recorded in the state are kept (ignore_changes), so no diff appears.
run "en41_ac6_apply_placeholder" {
  command = apply

  assert {
    condition     = aws_lambda_function.this.source_code_hash == "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    error_message = "The first apply must record the placeholder hash."
  }
}

run "en41_ac6_code_changes_are_ignored" {
  command = plan

  override_data {
    target = data.archive_file.placeholder
    values = {
      output_base64sha256 = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="
    }
  }

  assert {
    condition     = aws_lambda_function.this.source_code_hash == "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    error_message = "A new code hash must not produce a diff on source_code_hash."
  }

  assert {
    condition     = endswith(aws_lambda_function.this.filename, "/.build/sc-dev-tickets.zip")
    error_message = "The placeholder archive path must stay stable (output_path is a configuration value)."
  }
}

# EN-41-AC7: the boundary must belong to the environment (name contains name_prefix)
run "en41_ac7_permissions_boundary_of_another_environment_refused" {
  command = plan

  variables {
    permissions_boundary_arn = "arn:aws:iam::123456789012:policy/sc-prod-boundary"
  }

  expect_failures = [var.permissions_boundary_arn]
}

run "en41_ac7_permissions_boundary_with_path_accepted" {
  command = plan

  variables {
    permissions_boundary_arn = "arn:aws:iam::123456789012:policy/boundaries/sc-dev-boundary"
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == "arn:aws:iam::123456789012:policy/boundaries/sc-dev-boundary"
    error_message = "A boundary whose name contains name_prefix must be accepted, whatever its path."
  }
}

run "en41_ac7_environment_key_must_be_a_key_arn" {
  command = plan

  variables {
    environment_kms_key_arn = "alias/sc-dev-data"
  }

  expect_failures = [var.environment_kms_key_arn]
}

# EN-41-AC7: forbidden patterns of extra_policy_json
run "en41_ac7_extra_policy_resource_wildcard_refused" {
  command = plan

  variables {
    extra_policy_json = jsonencode({
      Version   = "2012-10-17"
      Statement = [{ Effect = "Allow", Action = ["dynamodb:GetItem"], Resource = "*" }]
    })
  }

  expect_failures = [var.extra_policy_json]
}

run "en41_ac7_extra_policy_resource_wildcard_in_list_refused" {
  command = plan

  variables {
    extra_policy_json = jsonencode({
      Version   = "2012-10-17"
      Statement = [{ Effect = "Allow", Action = ["dynamodb:GetItem"], Resource = ["arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-tickets", "*"] }]
    })
  }

  expect_failures = [var.extra_policy_json]
}

run "en41_ac7_extra_policy_not_action_refused" {
  command = plan

  variables {
    extra_policy_json = jsonencode({
      Version   = "2012-10-17"
      Statement = [{ Effect = "Allow", NotAction = ["iam:*"], Resource = "arn:aws:s3:::sc-dev-bucket" }]
    })
  }

  expect_failures = [var.extra_policy_json]
}

run "en41_ac7_extra_policy_not_resource_refused" {
  command = plan

  variables {
    extra_policy_json = jsonencode({
      Version   = "2012-10-17"
      Statement = [{ Effect = "Allow", Action = ["s3:GetObject"], NotResource = "arn:aws:s3:::sc-dev-other/*" }]
    })
  }

  expect_failures = [var.extra_policy_json]
}

run "en41_ac7_extra_policy_wildcard_service_refused" {
  command = plan

  variables {
    extra_policy_json = jsonencode({
      Version   = "2012-10-17"
      Statement = [{ Effect = "Allow", Action = ["*:*"], Resource = "arn:aws:s3:::sc-dev-bucket" }]
    })
  }

  expect_failures = [var.extra_policy_json]
}

run "en41_ac7_extra_policy_iam_wildcard_refused" {
  command = plan

  variables {
    extra_policy_json = jsonencode({
      Version   = "2012-10-17"
      Statement = [{ Effect = "Allow", Action = ["iam:*"], Resource = "arn:aws:iam::123456789012:role/sc-dev-other" }]
    })
  }

  expect_failures = [var.extra_policy_json]
}

run "en41_ac7_extra_policy_iam_pass_role_refused" {
  command = plan

  variables {
    extra_policy_json = jsonencode({
      Version   = "2012-10-17"
      Statement = [{ Effect = "Allow", Action = "iam:PassRole", Resource = "arn:aws:iam::123456789012:role/sc-dev-other" }]
    })
  }

  expect_failures = [var.extra_policy_json]
}

run "en41_ac7_extra_policy_sts_wildcard_refused" {
  command = plan

  variables {
    extra_policy_json = jsonencode({
      Version   = "2012-10-17"
      Statement = [{ Effect = "Allow", Action = ["sts:*"], Resource = "arn:aws:iam::123456789012:role/sc-dev-other" }]
    })
  }

  expect_failures = [var.extra_policy_json]
}

run "en41_ac7_extra_policy_kms_wildcard_refused" {
  command = plan

  variables {
    extra_policy_json = jsonencode({
      Version   = "2012-10-17"
      Statement = [{ Effect = "Allow", Action = ["kms:*"], Resource = "arn:aws:kms:eu-west-3:123456789012:key/11111111-1111-1111-1111-111111111111" }]
    })
  }

  expect_failures = [var.extra_policy_json]
}

run "en41_ac7_extra_policy_lambda_update_refused" {
  command = plan

  variables {
    extra_policy_json = jsonencode({
      Version   = "2012-10-17"
      Statement = [{ Effect = "Allow", Action = ["lambda:Update*"], Resource = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-other" }]
    })
  }

  expect_failures = [var.extra_policy_json]
}

run "en41_ac7_extra_policy_lambda_function_wildcard_refused" {
  command = plan

  variables {
    extra_policy_json = jsonencode({
      Version   = "2012-10-17"
      Statement = [{ Effect = "Allow", Action = ["lambda:*Function*"], Resource = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-other" }]
    })
  }

  expect_failures = [var.extra_policy_json]
}

run "en41_ac7_extra_policy_lambda_wildcard_refused" {
  command = plan

  variables {
    extra_policy_json = jsonencode({
      Version   = "2012-10-17"
      Statement = [{ Effect = "Allow", Action = ["lambda:*"], Resource = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-other" }]
    })
  }

  expect_failures = [var.extra_policy_json]
}

run "en41_ac7_extra_policy_scoped_statements_accepted" {
  command = plan

  variables {
    extra_policy_json = jsonencode({
      Version = "2012-10-17"
      Statement = [
        { Sid = "Table", Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:Query"], Resource = ["arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-tickets", "arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-tickets/index/*"] },
        { Sid = "Key", Effect = "Allow", Action = ["kms:Decrypt"], Resource = "arn:aws:kms:eu-west-3:123456789012:key/11111111-1111-1111-1111-111111111111" },
        { Sid = "Invoke", Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-other:live" },
        { Sid = "DenyAll", Effect = "Deny", Action = ["s3:DeleteObject"], Resource = "*" },
      ]
    })
  }

  assert {
    condition     = length(data.aws_iam_policy_document.execution.source_policy_documents) == 1
    error_message = "A scoped extra policy must be accepted and merged."
  }
}

# ADR-0014 (workshop exception): a null boundary is accepted and no boundary is attached to the role
run "adr0014_null_permissions_boundary_is_accepted" {
  command = plan

  variables {
    permissions_boundary_arn = null
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == null
    error_message = "A null permissions_boundary_arn must attach no boundary to the role."
  }
}

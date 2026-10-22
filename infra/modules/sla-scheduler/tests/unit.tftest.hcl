mock_provider "aws" {
  # Fake documentation account ID, used only to keep names and conditions predictable.
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

  # The mock returns random strings for computed attributes, which the role, role policy and queue policy reject as
  # invalid JSON. The invariants are asserted on the document arguments (known at plan), not on the JSON.
  override_data {
    target = data.aws_iam_policy_document.trust
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.scheduler
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.tickets_schedules
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

  # Computed ARNs are unknown at plan time and are consumed by the policy documents.
  override_resource {
    target = aws_iam_role.scheduler
    values = {
      arn = "arn:aws:iam::123456789012:role/sc-dev-sla-scheduler"
    }
  }

  override_resource {
    target = aws_sqs_queue.dlq
    values = {
      arn = "arn:aws:sqs:eu-west-3:123456789012:sc-dev-sla-dlq"
      url = "https://sqs.eu-west-3.amazonaws.com/123456789012/sc-dev-sla-dlq"
    }
  }
}

variables {
  name_prefix = "sc-dev"
  # Documentation account ID and placeholder names.
  escalation_alias_arn     = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-escalation:live"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/sc-dev-workload-boundary"
  dlq_kms_key_arn          = "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000"
}

# EN44-AC1: the SLA schedule group is named <prefix>-sla
run "en44_ac1_schedule_group_named_after_prefix" {
  command = plan

  assert {
    condition     = aws_scheduler_schedule_group.sla.name == "sc-dev-sla"
    error_message = "The schedule group must be named <name_prefix>-sla."
  }

  assert {
    condition     = aws_scheduler_schedule_group.sla.tags["Name"] == "sc-dev-sla"
    error_message = "The schedule group must be tagged with its name."
  }
}

# EN44-AC1: extra tags are merged on every taggable resource
run "en44_ac1_extra_tags_applied" {
  command = plan

  variables {
    tags = { Owner = "ops" }
  }

  assert {
    condition     = aws_scheduler_schedule_group.sla.tags["Owner"] == "ops" && aws_iam_role.scheduler.tags["Owner"] == "ops" && one(aws_sqs_queue.dlq).tags["Owner"] == "ops"
    error_message = "Extra tags must be applied to the group, the role and the queue."
  }
}

# EN44-AC2: the trust policy only lets the scheduler service assume the role, for this account and this group
run "en44_ac2_trust_policy_pinned_to_group" {
  command = plan

  assert {
    condition     = length(data.aws_iam_policy_document.trust.statement) == 1
    error_message = "The trust policy must contain a single statement."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.trust.statement :
      s.effect == "Allow" && toset(s.actions) == toset(["sts:AssumeRole"]) &&
      alltrue([for p in s.principals : p.type == "Service" && p.identifiers == toset(["scheduler.amazonaws.com"])])
    ])
    error_message = "Only scheduler.amazonaws.com may assume the execution role."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.trust.statement :
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceAccount" && c.test == "StringEquals" && toset(c.values) == toset(["123456789012"])
      ])
    ])
    error_message = "The trust policy must be conditioned by aws:SourceAccount."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.trust.statement :
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceArn" && c.test == "StringEquals" &&
        toset(c.values) == toset(["arn:aws:scheduler:eu-west-3:123456789012:schedule-group/sc-dev-sla"])
      ])
    ])
    error_message = "The trust policy must be conditioned by aws:SourceArn equal to the SLA schedule group ARN."
  }
}

# EN44-AC2: the role carries the permissions boundary
run "en44_ac2_role_has_permissions_boundary" {
  command = plan

  assert {
    condition     = aws_iam_role.scheduler.name == "sc-dev-sla-scheduler"
    error_message = "The role must be named <name_prefix>-sla-scheduler."
  }

  assert {
    condition     = aws_iam_role.scheduler.permissions_boundary == "arn:aws:iam::123456789012:policy/sc-dev-workload-boundary"
    error_message = "The permissions boundary must be attached to the scheduler execution role."
  }
}

# EN44-AC2: the role may only invoke the live alias of escalation (and write to the DLQ)
run "en44_ac2_role_policy_invokes_live_alias_only" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.scheduler.statement :
      s.sid == "InvokeEscalationLiveAlias" && s.effect == "Allow" &&
      toset(s.actions) == toset(["lambda:InvokeFunction"]) &&
      toset(s.resources) == toset(["arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-escalation:live"])
    ])
    error_message = "The role must be allowed lambda:InvokeFunction on the escalation live alias ARN only."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.scheduler.statement :
      s.effect == "Allow" && !anytrue([for a in s.actions : a == "*" || endswith(a, ":*")])
    ])
    error_message = "The role policy must list explicit actions."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.scheduler.statement :
      !anytrue([for r in s.resources : strcontains(r, "*")])
    ])
    error_message = "The role policy must not contain wildcard resources."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.scheduler.statement :
      anytrue([for a in s.actions : startswith(a, "lambda:")]) ? toset(s.actions) == toset(["lambda:InvokeFunction"]) : true
    ])
    error_message = "lambda:InvokeFunction is the only Lambda action the role may have."
  }

  assert {
    condition     = aws_iam_role_policy.scheduler.role == "sc-dev-sla-scheduler"
    error_message = "The policy must be attached to the scheduler execution role."
  }
}

# EN44-AC2: the role can write to the DLQ and use its key, only through SQS
run "en44_ac2_role_policy_dlq_and_key_scoped" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.scheduler.statement :
      s.sid == "SendFailedEventsToDlq" && s.effect == "Allow" &&
      toset(s.actions) == toset(["sqs:SendMessage"]) &&
      toset(s.resources) == toset(["arn:aws:sqs:eu-west-3:123456789012:sc-dev-sla-dlq"])
    ])
    error_message = "The role must be allowed sqs:SendMessage on the DLQ ARN only."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.scheduler.statement :
      s.sid == "UseDlqKey" && s.effect == "Allow" &&
      toset(s.actions) == toset(["kms:Decrypt", "kms:GenerateDataKey"]) &&
      toset(s.resources) == toset(["arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000"]) &&
      anytrue([
        for c in s.condition :
        c.variable == "kms:ViaService" && c.test == "StringEquals" && toset(c.values) == toset(["sqs.eu-west-3.amazonaws.com"])
      ])
    ])
    error_message = "The role must use the DLQ key through SQS only."
  }
}

# EN44-AC3: tickets creates and deletes schedules in the SLA group only
run "en44_ac3_tickets_schedules_scoped_to_group" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.tickets_schedules.statement :
      s.sid == "ManageSlaSchedules" && s.effect == "Allow" &&
      toset(s.actions) == toset(["scheduler:CreateSchedule", "scheduler:DeleteSchedule"]) &&
      toset(s.resources) == toset(["arn:aws:scheduler:eu-west-3:123456789012:schedule/sc-dev-sla/*"])
    ])
    error_message = "tickets must manage schedules of the SLA group only."
  }
}

# EN44-AC3: iam:PassRole is limited to the scheduler execution role, for the scheduler service
run "en44_ac3_tickets_pass_role_limited_to_scheduler_role" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.tickets_schedules.statement :
      s.sid == "PassSchedulerRole" && s.effect == "Allow" &&
      toset(s.actions) == toset(["iam:PassRole"]) &&
      toset(s.resources) == toset(["arn:aws:iam::123456789012:role/sc-dev-sla-scheduler"]) &&
      anytrue([
        for c in s.condition :
        c.variable == "iam:PassedToService" && c.test == "StringEquals" && toset(c.values) == toset(["scheduler.amazonaws.com"])
      ])
    ])
    error_message = "iam:PassRole must be limited to the scheduler execution role and to scheduler.amazonaws.com."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.tickets_schedules.statement :
      contains(s.actions, "iam:PassRole") ? s.sid == "PassSchedulerRole" : true
    ])
    error_message = "Only PassSchedulerRole may grant iam:PassRole."
  }
}

# EN44-AC4: the DLQ is an SQS queue encrypted with the customer-managed key
run "en44_ac4_dlq_encrypted_with_cmk" {
  command = plan

  assert {
    condition     = one(aws_sqs_queue.dlq).name == "sc-dev-sla-dlq"
    error_message = "The queue must be named <name_prefix>-sla-dlq."
  }

  assert {
    condition     = one(aws_sqs_queue.dlq).kms_master_key_id == "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000"
    error_message = "The DLQ must be encrypted with the given customer-managed key."
  }

  assert {
    condition     = one(aws_sqs_queue.dlq).message_retention_seconds == 1209600
    error_message = "The DLQ retention must default to 14 days."
  }
}

# EN44-AC4: the DLQ retention follows the variable
run "en44_ac4_dlq_retention_configurable" {
  command = plan

  variables {
    dlq_message_retention_seconds = 345600
  }

  assert {
    condition     = one(aws_sqs_queue.dlq).message_retention_seconds == 345600
    error_message = "The DLQ retention must follow dlq_message_retention_seconds."
  }
}

# EN44-AC4: the DLQ policy denies non-TLS access
run "en44_ac4_dlq_policy_denies_insecure_transport" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.dlq[0].statement :
      s.sid == "DenyInsecureTransport" && s.effect == "Deny" && anytrue([
        for c in s.condition :
        c.variable == "aws:SecureTransport" && c.test == "Bool" && contains(c.values, "false")
      ])
    ])
    error_message = "The DLQ policy must deny requests without aws:SecureTransport."
  }

  assert {
    condition     = alltrue([for s in data.aws_iam_policy_document.dlq[0].statement : s.effect == "Deny"])
    error_message = "The DLQ policy must only contain Deny statements; access is granted by IAM."
  }
}

# EN44-AC4: the DLQ is optional and removes its statements when disabled
run "en44_ac4_dlq_disabled" {
  command = plan

  variables {
    enable_dlq      = false
    dlq_kms_key_arn = null
  }

  assert {
    condition     = length(aws_sqs_queue.dlq) == 0 && length(aws_sqs_queue_policy.dlq) == 0
    error_message = "No queue must be created when enable_dlq is false."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.scheduler.statement :
      !anytrue([for a in s.actions : startswith(a, "sqs:") || startswith(a, "kms:")])
    ])
    error_message = "The role policy must not grant SQS or KMS access when enable_dlq is false."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.scheduler.statement) == 1
    error_message = "Only the Lambda invocation statement must remain when enable_dlq is false."
  }
}

# EN44-AC4: the DLQ requires a key
run "en44_ac4_rejects_dlq_without_kms_key" {
  command = plan

  variables {
    dlq_kms_key_arn = null
  }

  expect_failures = [var.dlq_kms_key_arn]
}

# EN44-AC4: the DLQ key must be a key ARN, not an alias
run "en44_ac4_rejects_alias_as_kms_key" {
  command = plan

  variables {
    dlq_kms_key_arn = "arn:aws:kms:eu-west-3:123456789012:alias/sc-dev-data"
  }

  expect_failures = [var.dlq_kms_key_arn]
}

# EN44-AC4: a key without a DLQ is a mistake
run "en44_ac4_rejects_kms_key_without_dlq" {
  command = plan

  variables {
    enable_dlq = false
  }

  expect_failures = [var.dlq_kms_key_arn]
}

# EN44-AC4: rejects a retention outside the SQS limits
run "en44_ac4_rejects_retention_above_14_days" {
  command = plan

  variables {
    dlq_message_retention_seconds = 1209601
  }

  expect_failures = [var.dlq_message_retention_seconds]
}

# EN44-AC4: rejects a retention below one minute
run "en44_ac4_rejects_retention_below_60_seconds" {
  command = plan

  variables {
    dlq_message_retention_seconds = 59
  }

  expect_failures = [var.dlq_message_retention_seconds]
}

# EN44-AC2: rejects the unqualified function ARN
run "en44_ac2_rejects_unqualified_function_arn" {
  command = plan

  variables {
    escalation_alias_arn = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-escalation"
  }

  expect_failures = [var.escalation_alias_arn]
}

# EN44-AC2: rejects a version number or $LATEST instead of the live alias
run "en44_ac2_rejects_version_arn" {
  command = plan

  variables {
    escalation_alias_arn = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-escalation:3"
  }

  expect_failures = [var.escalation_alias_arn]
}

# EN44-AC2: rejects an alias other than live
run "en44_ac2_rejects_other_alias" {
  command = plan

  variables {
    escalation_alias_arn = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-escalation:canary"
  }

  expect_failures = [var.escalation_alias_arn]
}

# EN44-AC2: rejects a wildcard in the alias ARN
run "en44_ac2_rejects_wildcard_alias_arn" {
  command = plan

  variables {
    escalation_alias_arn = "arn:aws:lambda:eu-west-3:123456789012:function:*:live"
  }

  expect_failures = [var.escalation_alias_arn]
}

# EN44-AC2: rejects a permissions boundary that is not a policy ARN
run "en44_ac2_rejects_invalid_permissions_boundary" {
  command = plan

  variables {
    permissions_boundary_arn = "sc-dev-workload-boundary"
  }

  expect_failures = [var.permissions_boundary_arn]
}

# EN44-AC1: rejects an invalid name_prefix
run "en44_ac1_rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Bad_Prefix"
  }

  expect_failures = [var.name_prefix]
}

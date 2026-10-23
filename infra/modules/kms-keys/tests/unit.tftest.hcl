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

  # The policy document statements are computed from the module code and inspected by the assertions.
  # The json attribute is overridden with valid JSON because mock_provider returns random strings.
  # Assertions target the data source ARGUMENTS (statement blocks), never the json.
  override_data {
    target = data.aws_iam_policy_document.key
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.alert_rule
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.alert_topic
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # Computed attributes consumed by the aliases and by the alert rule pattern.
  override_resource {
    target = aws_kms_key.this
    values = {
      arn    = "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000"
      key_id = "00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  name_prefix                 = "sc-dev"
  environment                 = "dev"
  kms_deletion_window_in_days = 7
  # Placeholder role names in the documentation account.
  admin_principal_arns = [
    "arn:aws:iam::123456789012:role/sc-bootstrap-admin",
    "arn:aws:iam::123456789012:user/sc-break-glass",
  ]
}

# EN14-AC1: three keys, aliases prefixed with the environment prefix
run "en14_ac1_three_keys_with_prefixed_aliases" {
  command = plan

  assert {
    condition     = toset(keys(aws_kms_key.this)) == toset(["data", "logs", "ai"])
    error_message = "The default keys must be data, logs and ai."
  }

  assert {
    condition     = aws_kms_alias.this["data"].name == "alias/sc-dev-data" && aws_kms_alias.this["logs"].name == "alias/sc-dev-logs" && aws_kms_alias.this["ai"].name == "alias/sc-dev-ai"
    error_message = "Aliases must be alias/<prefix>-<domain>."
  }

  assert {
    condition     = alltrue([for domain, a in aws_kms_alias.this : a.target_key_id == aws_kms_key.this[domain].key_id])
    error_message = "Every alias must target the key of its domain."
  }

  assert {
    condition     = alltrue([for k in aws_kms_key.this : k.key_usage == "ENCRYPT_DECRYPT" && k.customer_master_key_spec == "SYMMETRIC_DEFAULT"])
    error_message = "Keys must be symmetric encrypt/decrypt keys."
  }
}

# EN14-AC1: keys carry the Environment tag and the extra tags
run "en14_ac1_keys_tagged_with_environment" {
  command = plan

  variables {
    tags = { Owner = "ops" }
  }

  assert {
    condition     = alltrue([for k in aws_kms_key.this : k.tags["Environment"] == "dev" && k.tags["Owner"] == "ops"])
    error_message = "Every key must carry the Environment tag and the extra tags."
  }

  assert {
    condition     = alltrue([for domain, k in aws_kms_key.this : k.tags["Name"] == "sc-dev-${domain}"])
    error_message = "Every key must be named <prefix>-<domain>."
  }
}

# EN14-AC1: the key map drives the keys that are created
run "en14_ac1_key_map_is_configurable" {
  command = plan

  variables {
    keys = {
      data = { description = "Data key" }
    }
  }

  assert {
    condition     = toset(keys(aws_kms_key.this)) == toset(["data"]) && toset(keys(aws_kms_alias.this)) == toset(["data"])
    error_message = "Only the keys in the map must be created."
  }

  assert {
    condition     = aws_kms_key.this["data"].description == "Data key"
    error_message = "The key description must come from the map."
  }
}

# EN14-AC4: the key ARNs, IDs and aliases are exposed by domain for the SSM publication
run "en14_ac4_outputs_by_domain" {
  command = plan

  assert {
    condition     = toset(keys(output.key_arns)) == toset(["data", "logs", "ai"]) && toset(keys(output.key_ids)) == toset(["data", "logs", "ai"])
    error_message = "key_arns and key_ids must be keyed by domain."
  }

  assert {
    condition     = output.alias_names["logs"] == "alias/sc-dev-logs"
    error_message = "alias_names must expose the alias of each key."
  }

  assert {
    condition     = output.deletion_alert_rule_arn == null
    error_message = "The alert rule ARN must be null when alerts are disabled."
  }
}

# EN14-AC1: rejects an invalid name_prefix
run "en14_ac1_rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Bad_Prefix"
  }

  expect_failures = [var.name_prefix]
}

# EN14-AC1: rejects an invalid environment
run "en14_ac1_rejects_invalid_environment" {
  command = plan

  variables {
    environment = "Dev"
  }

  expect_failures = [var.environment]
}

# EN14-AC1: rejects an invalid key name
run "en14_ac1_rejects_invalid_key_name" {
  command = plan

  variables {
    keys = {
      "Bad_Domain" = { description = "Bad" }
    }
  }

  expect_failures = [var.keys]
}

# EN14-AC1: rejects an empty key map
run "en14_ac1_rejects_empty_key_map" {
  command = plan

  variables {
    keys = {}
  }

  expect_failures = [var.keys]
}

# EN14-AC1: rejects a service grant whose domain key is not in the map
run "en14_ac1_rejects_grant_without_matching_key" {
  command = plan

  variables {
    keys = {
      data = { description = "Data key" }
    }
    enable_cloudwatch_logs = true
  }

  expect_failures = [var.keys]
}

# EN14-AC2: every key rotates automatically and the deletion window follows the variable
run "en14_ac2_rotation_enabled" {
  command = plan

  variables {
    kms_deletion_window_in_days = 30
  }

  assert {
    condition     = alltrue([for k in aws_kms_key.this : k.enable_key_rotation == true])
    error_message = "KMS key rotation must be enabled on every key."
  }

  assert {
    condition     = alltrue([for k in aws_kms_key.this : k.deletion_window_in_days == 30])
    error_message = "The deletion window must follow the variable."
  }
}

# EN14-AC2: rejects a KMS deletion window below 7 days
run "en14_ac2_rejects_deletion_window_below_7" {
  command = plan

  variables {
    kms_deletion_window_in_days = 6
  }

  expect_failures = [var.kms_deletion_window_in_days]
}

# EN14-AC2: rejects a KMS deletion window above 30 days
run "en14_ac2_rejects_deletion_window_above_30" {
  command = plan

  variables {
    kms_deletion_window_in_days = 31
  }

  expect_failures = [var.kms_deletion_window_in_days]
}

# EN14-AC3: without any grant, each key policy only has the three base statements
run "en14_ac3_base_statements_only_by_default" {
  command = plan

  assert {
    condition = alltrue([
      for domain, d in data.aws_iam_policy_document.key :
      toset([for s in d.statement : s.sid]) == toset(["EnableIamDelegation", "RootLockoutRecovery", "KeyAdministration"])
    ])
    error_message = "No service grant may exist unless an input enables it."
  }
}

# EN14-AC3: base statements delegate to IAM, restrict the root and reserve administration to the admin principals
run "en14_ac3_base_statements_scoped_to_named_principals" {
  command = plan

  assert {
    condition = alltrue([
      for domain, d in data.aws_iam_policy_document.key :
      anytrue([
        for s in d.statement :
        s.sid == "EnableIamDelegation" && s.effect == "Allow" &&
        alltrue([for p in s.principals : p.type == "AWS" && toset(p.identifiers) == toset(["arn:aws:iam::123456789012:root"])]) &&
        !anytrue([for a in s.actions : contains(["kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:PutKeyPolicy"], a)])
      ])
    ])
    error_message = "EnableIamDelegation must grant the account root usage actions only."
  }

  assert {
    condition = alltrue([
      for domain, d in data.aws_iam_policy_document.key :
      anytrue([
        for s in d.statement :
        s.sid == "RootLockoutRecovery" && toset(s.actions) == toset(["kms:DescribeKey", "kms:GetKeyPolicy", "kms:PutKeyPolicy"])
      ])
    ])
    error_message = "The account root must keep exactly DescribeKey, GetKeyPolicy and PutKeyPolicy for lockout recovery."
  }

  assert {
    condition = alltrue([
      for domain, d in data.aws_iam_policy_document.key :
      anytrue([
        for s in d.statement :
        s.sid == "KeyAdministration" && s.effect == "Allow" &&
        alltrue([for p in s.principals : p.type == "AWS" && toset(p.identifiers) == toset(var.admin_principal_arns)]) &&
        contains(s.actions, "kms:ScheduleKeyDeletion") && contains(s.actions, "kms:DisableKey")
      ])
    ])
    error_message = "KeyAdministration must be granted to exactly admin_principal_arns."
  }

  assert {
    condition = alltrue([
      for domain, d in data.aws_iam_policy_document.key : alltrue([
        for s in d.statement :
        s.sid == "KeyAdministration" if anytrue([for a in s.actions : contains(["kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:PutKeyPolicy"], a)]) && s.sid != "RootLockoutRecovery"
      ])
    ])
    error_message = "Only KeyAdministration (and the root lockout recovery for PutKeyPolicy) may administer a key."
  }
}

# EN14-AC3: with every grant enabled, no policy has a "*" principal or a wildcard action
run "en14_ac3_no_wildcard_principal_with_all_grants" {
  command = plan

  variables {
    enable_cloudwatch_logs                 = true
    enable_cloudtrail                      = true
    enable_config                          = true
    enable_log_delivery                    = true
    data_via_services                      = ["dynamodb", "s3", "sqs"]
    cloudfront_distribution_arns           = ["arn:aws:cloudfront::123456789012:distribution/E1ABCDEFGHIJKL"]
    guardduty_malware_protection_role_arns = ["arn:aws:iam::123456789012:role/sc-dev-malware-protection"]
    enable_bedrock                         = true
    ai_via_services                        = ["bedrock", "s3"]
  }

  assert {
    condition = alltrue([
      for domain, d in data.aws_iam_policy_document.key : alltrue([
        for s in d.statement :
        alltrue([for p in s.principals : p.type != "*" && !contains(p.identifiers, "*")])
      ])
    ])
    error_message = "No key policy may contain a \"*\" principal."
  }

  assert {
    condition = alltrue([
      for domain, d in data.aws_iam_policy_document.key : alltrue([
        for s in d.statement :
        !anytrue([for a in s.actions : a == "*" || a == "kms:*"])
      ])
    ])
    error_message = "Key policies must list explicit KMS actions."
  }

  assert {
    condition = alltrue([
      for domain, d in data.aws_iam_policy_document.key : alltrue([
        for s in d.statement : length(s.principals) > 0 && s.effect == "Allow"
      ])
    ])
    error_message = "Every statement must name its principals and allow."
  }
}

# EN14-AC3: every service grant carries at least one condition, and service principals are tied to this account
run "en14_ac3_every_service_grant_is_conditioned" {
  command = plan

  variables {
    enable_cloudwatch_logs                 = true
    enable_cloudtrail                      = true
    enable_config                          = true
    enable_log_delivery                    = true
    data_via_services                      = ["dynamodb", "s3", "sqs"]
    cloudfront_distribution_arns           = ["arn:aws:cloudfront::123456789012:distribution/E1ABCDEFGHIJKL"]
    guardduty_malware_protection_role_arns = ["arn:aws:iam::123456789012:role/sc-dev-malware-protection"]
    enable_bedrock                         = true
    ai_via_services                        = ["bedrock", "s3"]
  }

  assert {
    condition = alltrue([
      for domain, d in data.aws_iam_policy_document.key : alltrue([
        for s in d.statement :
        length(s.condition) >= 1
        if !contains(["EnableIamDelegation", "RootLockoutRecovery", "KeyAdministration"], s.sid)
      ])
    ])
    error_message = "Every service grant must carry at least one condition."
  }

  assert {
    condition = alltrue([
      for domain, d in data.aws_iam_policy_document.key : alltrue([
        for s in d.statement :
        anytrue([
          for c in s.condition :
          contains(["aws:SourceAccount", "aws:SourceArn", "kms:ViaService", "kms:CallerAccount", "kms:EncryptionContext:aws:logs:arn"], c.variable)
        ])
        if anytrue([for p in s.principals : p.type == "Service"])
      ])
    ])
    error_message = "Every service principal grant must be tied to the account (SourceArn, SourceAccount, encryption context or ViaService)."
  }

  assert {
    condition = alltrue([
      for domain, d in data.aws_iam_policy_document.key : alltrue([
        for s in d.statement :
        anytrue([for c in s.condition : c.variable == "kms:CallerAccount" && toset(c.values) == toset(["123456789012"])])
        if anytrue([for c in s.condition : c.variable == "kms:ViaService"])
      ])
    ])
    error_message = "Every kms:ViaService grant must also pin kms:CallerAccount to this account."
  }
}

# EN14-AC3: grants only land on the key of their domain
run "en14_ac3_grants_land_on_their_own_key" {
  command = plan

  variables {
    enable_cloudwatch_logs                 = true
    enable_cloudtrail                      = true
    enable_config                          = true
    enable_log_delivery                    = true
    data_via_services                      = ["dynamodb"]
    cloudfront_distribution_arns           = ["arn:aws:cloudfront::123456789012:distribution/E1ABCDEFGHIJKL"]
    guardduty_malware_protection_role_arns = ["arn:aws:iam::123456789012:role/sc-dev-malware-protection"]
    enable_bedrock                         = true
    ai_via_services                        = ["bedrock"]
  }

  assert {
    condition = toset([for s in data.aws_iam_policy_document.key["logs"].statement : s.sid]) == toset([
      "EnableIamDelegation", "RootLockoutRecovery", "KeyAdministration",
      "AllowCloudWatchLogs", "AllowCloudTrailEncrypt", "AllowCloudTrailDescribeKey", "AllowConfigServiceLinkedRole", "AllowLogDelivery",
    ])
    error_message = "The logs key must carry the logs grants only."
  }

  assert {
    condition = toset([for s in data.aws_iam_policy_document.key["data"].statement : s.sid]) == toset([
      "EnableIamDelegation", "RootLockoutRecovery", "KeyAdministration",
      "AllowAccountUsageViaServices", "AllowCloudFrontOriginAccessControl", "AllowGuardDutyMalwareProtection",
    ])
    error_message = "The data key must carry the data grants only."
  }

  assert {
    condition = toset([for s in data.aws_iam_policy_document.key["ai"].statement : s.sid]) == toset([
      "EnableIamDelegation", "RootLockoutRecovery", "KeyAdministration",
      "AllowBedrockKnowledgeBases", "AllowAccountUsageViaServices",
    ])
    error_message = "The ai key must carry the ai grants only."
  }
}

# EN14-AC3: CloudWatch Logs only for log groups of this account and region matching the name patterns
run "en14_ac3_logs_cloudwatch_grant_conditioned" {
  command = plan

  variables {
    enable_cloudwatch_logs  = true
    log_group_name_patterns = ["/aws/lambda/sc-dev-*"]
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.key["logs"].statement :
      s.sid == "AllowCloudWatchLogs" && s.effect == "Allow" &&
      alltrue([for p in s.principals : p.type == "Service" && toset(p.identifiers) == toset(["logs.eu-west-3.amazonaws.com"])]) &&
      toset(s.actions) == toset(["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*"]) &&
      anytrue([
        for c in s.condition :
        c.variable == "kms:EncryptionContext:aws:logs:arn" && c.test == "ArnLike" && toset(c.values) == toset([
          "arn:aws:logs:eu-west-3:123456789012:log-group:sc-dev-*",
          "arn:aws:logs:eu-west-3:123456789012:log-group:/aws/lambda/sc-dev-*",
        ])
      ])
    ])
    error_message = "CloudWatch Logs must be limited by the log group ARN encryption context in this account and region."
  }
}

# EN14-AC3: CloudTrail may only generate data keys for trails of this account
run "en14_ac3_logs_cloudtrail_grant_conditioned" {
  command = plan

  variables {
    enable_cloudtrail = true
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.key["logs"].statement :
      s.sid == "AllowCloudTrailEncrypt" && s.effect == "Allow" &&
      alltrue([for p in s.principals : p.type == "Service" && toset(p.identifiers) == toset(["cloudtrail.amazonaws.com"])]) &&
      toset(s.actions) == toset(["kms:GenerateDataKey*"]) &&
      anytrue([
        for c in s.condition :
        c.variable == "kms:EncryptionContext:aws:cloudtrail:arn" && c.test == "StringLike" && toset(c.values) == toset(["arn:aws:cloudtrail:*:123456789012:trail/*"])
      ]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceAccount" && c.test == "StringEquals" && toset(c.values) == toset(["123456789012"])
      ])
    ])
    error_message = "CloudTrail GenerateDataKey must be limited to trails and the source account of this account."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.key["logs"].statement :
      s.sid == "AllowCloudTrailDescribeKey" && toset(s.actions) == toset(["kms:DescribeKey"]) &&
      alltrue([for p in s.principals : p.type == "Service" && toset(p.identifiers) == toset(["cloudtrail.amazonaws.com"])]) &&
      anytrue([for c in s.condition : c.variable == "aws:SourceAccount" && toset(c.values) == toset(["123456789012"])])
    ])
    error_message = "CloudTrail DescribeKey must be limited to the source account."
  }
}

# EN14-AC3: the Config service-linked role gets Decrypt and GenerateDataKey through S3 only
run "en14_ac3_logs_config_grant_conditioned" {
  command = plan

  variables {
    enable_config = true
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.key["logs"].statement :
      s.sid == "AllowConfigServiceLinkedRole" && s.effect == "Allow" &&
      alltrue([
        for p in s.principals :
        p.type == "AWS" && toset(p.identifiers) == toset(["arn:aws:iam::123456789012:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"])
      ]) &&
      toset(s.actions) == toset(["kms:Decrypt", "kms:GenerateDataKey"]) &&
      anytrue([for c in s.condition : c.variable == "kms:ViaService" && toset(c.values) == toset(["s3.eu-west-3.amazonaws.com"])]) &&
      anytrue([for c in s.condition : c.variable == "kms:CallerAccount" && toset(c.values) == toset(["123456789012"])])
    ])
    error_message = "AWS Config must be limited to its service-linked role, through S3, for this account."
  }
}

# EN14-AC3: vended log delivery is limited to delivery sources of this account
run "en14_ac3_logs_delivery_grant_conditioned" {
  command = plan

  variables {
    enable_log_delivery = true
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.key["logs"].statement :
      s.sid == "AllowLogDelivery" && s.effect == "Allow" &&
      alltrue([for p in s.principals : p.type == "Service" && toset(p.identifiers) == toset(["delivery.logs.amazonaws.com"])]) &&
      anytrue([for c in s.condition : c.variable == "aws:SourceAccount" && c.test == "StringEquals" && toset(c.values) == toset(["123456789012"])]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceArn" && c.test == "ArnLike" && toset(c.values) == toset(["arn:aws:logs:eu-west-3:123456789012:delivery-source:*"])
      ])
    ])
    error_message = "Log delivery must be limited by aws:SourceAccount and aws:SourceArn of this account."
  }
}

# EN14-AC3: data key usable by IAM-delegated principals only through the listed services
run "en14_ac3_data_via_services_conditioned" {
  command = plan

  variables {
    data_via_services = ["sqs", "dynamodb", "s3"]
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.key["data"].statement :
      s.sid == "AllowAccountUsageViaServices" && s.effect == "Allow" &&
      alltrue([for p in s.principals : p.type == "AWS" && toset(p.identifiers) == toset(["arn:aws:iam::123456789012:root"])]) &&
      anytrue([
        for c in s.condition :
        c.variable == "kms:ViaService" && c.test == "StringEquals" && toset(c.values) == toset([
          "dynamodb.eu-west-3.amazonaws.com", "s3.eu-west-3.amazonaws.com", "sqs.eu-west-3.amazonaws.com",
        ])
      ]) &&
      anytrue([for c in s.condition : c.variable == "kms:CallerAccount" && toset(c.values) == toset(["123456789012"])])
    ])
    error_message = "The data key must be usable through dynamodb, s3 and sqs only, for this account."
  }
}

# EN14-AC3: CloudFront OAC is limited to the named distributions
run "en14_ac3_data_cloudfront_grant_conditioned" {
  command = plan

  variables {
    cloudfront_distribution_arns = ["arn:aws:cloudfront::123456789012:distribution/E1ABCDEFGHIJKL"]
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.key["data"].statement :
      s.sid == "AllowCloudFrontOriginAccessControl" && s.effect == "Allow" &&
      alltrue([for p in s.principals : p.type == "Service" && toset(p.identifiers) == toset(["cloudfront.amazonaws.com"])]) &&
      toset(s.actions) == toset(["kms:Decrypt", "kms:GenerateDataKey*"]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceArn" && c.test == "StringEquals" && toset(c.values) == toset(var.cloudfront_distribution_arns)
      ])
    ])
    error_message = "CloudFront must be limited by aws:SourceArn to the given distributions."
  }
}

# EN14-AC3: GuardDuty Malware Protection is limited to the named roles, through S3
run "en14_ac3_data_guardduty_grant_conditioned" {
  command = plan

  variables {
    guardduty_malware_protection_role_arns = ["arn:aws:iam::123456789012:role/sc-dev-malware-protection"]
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.key["data"].statement :
      s.sid == "AllowGuardDutyMalwareProtection" && s.effect == "Allow" &&
      alltrue([for p in s.principals : p.type == "AWS" && toset(p.identifiers) == toset(var.guardduty_malware_protection_role_arns)]) &&
      toset(s.actions) == toset(["kms:Decrypt", "kms:GenerateDataKey*"]) &&
      anytrue([for c in s.condition : c.variable == "kms:ViaService" && toset(c.values) == toset(["s3.eu-west-3.amazonaws.com"])]) &&
      anytrue([for c in s.condition : c.variable == "kms:CallerAccount" && toset(c.values) == toset(["123456789012"])])
    ])
    error_message = "GuardDuty Malware Protection must be limited to the given roles, through S3, for this account."
  }
}

# EN14-AC3: Bedrock is limited to Knowledge Bases of this account
run "en14_ac3_ai_bedrock_grant_conditioned" {
  command = plan

  variables {
    enable_bedrock  = true
    ai_via_services = ["s3", "bedrock"]
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.key["ai"].statement :
      s.sid == "AllowBedrockKnowledgeBases" && s.effect == "Allow" &&
      alltrue([for p in s.principals : p.type == "Service" && toset(p.identifiers) == toset(["bedrock.amazonaws.com"])]) &&
      anytrue([for c in s.condition : c.variable == "aws:SourceAccount" && c.test == "StringEquals" && toset(c.values) == toset(["123456789012"])]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceArn" && c.test == "ArnLike" && toset(c.values) == toset(["arn:aws:bedrock:eu-west-3:123456789012:knowledge-base/*"])
      ])
    ])
    error_message = "Bedrock must be limited by aws:SourceAccount and the knowledge-base aws:SourceArn."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.key["ai"].statement :
      s.sid == "AllowAccountUsageViaServices" &&
      anytrue([
        for c in s.condition :
        c.variable == "kms:ViaService" && toset(c.values) == toset(["bedrock.eu-west-3.amazonaws.com", "s3.eu-west-3.amazonaws.com"])
      ]) &&
      anytrue([for c in s.condition : c.variable == "kms:CallerAccount" && toset(c.values) == toset(["123456789012"])])
    ])
    error_message = "The ai key must be usable through bedrock and s3 only, for this account."
  }
}

# EN14-AC3: rejects an admin principal list that is empty, not an ARN, root or wildcard
run "en14_ac3_rejects_empty_admin_principal_arns" {
  command = plan

  variables {
    admin_principal_arns = []
  }

  expect_failures = [var.admin_principal_arns]
}

run "en14_ac3_rejects_root_and_wildcard_admin_principal" {
  command = plan

  variables {
    admin_principal_arns = ["arn:aws:iam::123456789012:root", "arn:aws:iam::123456789012:role/*"]
  }

  expect_failures = [var.admin_principal_arns]
}

# EN14-AC3: rejects grants inputs that could open the key too wide
run "en14_ac3_rejects_bare_wildcard_log_group_pattern" {
  command = plan

  variables {
    log_group_name_patterns = ["*"]
  }

  expect_failures = [var.log_group_name_patterns]
}

run "en14_ac3_rejects_unknown_via_service" {
  command = plan

  variables {
    data_via_services = ["lambda"]
  }

  expect_failures = [var.data_via_services]
}

run "en14_ac3_rejects_unknown_ai_via_service" {
  command = plan

  variables {
    ai_via_services = ["dynamodb"]
  }

  expect_failures = [var.ai_via_services]
}

run "en14_ac3_rejects_wildcard_cloudfront_distribution" {
  command = plan

  variables {
    cloudfront_distribution_arns = ["arn:aws:cloudfront::123456789012:distribution/*"]
  }

  expect_failures = [var.cloudfront_distribution_arns]
}

run "en14_ac3_rejects_wildcard_guardduty_role" {
  command = plan

  variables {
    guardduty_malware_protection_role_arns = ["arn:aws:iam::123456789012:role/*"]
  }

  expect_failures = [var.guardduty_malware_protection_role_arns]
}

# EN12 follow-up: no alert rule unless enabled
run "en14_ac3_alert_rule_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_event_rule.key_protection) == 0 && length(aws_cloudwatch_event_target.key_protection) == 0
    error_message = "The key protection alert must be disabled unless requested."
  }
}

# EN12 follow-up: alert rule matches ScheduleKeyDeletion and DisableKey on these keys and targets the SNS topic
run "en14_ac3_alert_rule_pattern" {
  command = plan

  variables {
    enable_deletion_alerts = true
    alert_topic_arn        = "arn:aws:sns:eu-west-3:123456789012:sc-dev-alerts"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.key_protection[0].name == "sc-dev-kms-key-protection"
    error_message = "The rule must be named <prefix>-kms-key-protection."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.key_protection[0].event_pattern).source == ["aws.kms"]
    error_message = "The rule must match KMS events."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.key_protection[0].event_pattern)["detail-type"] == ["AWS API Call via CloudTrail"]
    error_message = "The rule must match CloudTrail API call events."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.key_protection[0].event_pattern).detail.eventSource == ["kms.amazonaws.com"]
    error_message = "The rule must match the KMS event source."
  }

  assert {
    condition     = toset(jsondecode(aws_cloudwatch_event_rule.key_protection[0].event_pattern).detail.eventName) == toset(["ScheduleKeyDeletion", "DisableKey"])
    error_message = "The rule must match ScheduleKeyDeletion and DisableKey only."
  }

  assert {
    condition = toset(jsondecode(aws_cloudwatch_event_rule.key_protection[0].event_pattern).detail.requestParameters.keyId) == toset([
      "00000000-0000-0000-0000-000000000000",
      "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000",
      "alias/sc-dev-data",
      "alias/sc-dev-logs",
      "alias/sc-dev-ai",
    ])
    error_message = "The rule must match the ID, ARN and alias of the domain keys only."
  }

  assert {
    condition     = aws_cloudwatch_event_target.key_protection[0].arn == "arn:aws:sns:eu-west-3:123456789012:sc-dev-alerts"
    error_message = "The rule must publish to the alert topic."
  }
}

# EN12 follow-up: rejects alerts without a topic
run "en14_ac3_rejects_alerts_without_topic" {
  command = plan

  variables {
    enable_deletion_alerts = true
  }

  expect_failures = [var.alert_topic_arn]
}

# EN12 follow-up: rejects a topic that is not an SNS ARN
run "en14_ac3_rejects_invalid_alert_topic" {
  command = plan

  variables {
    alert_topic_arn = "sc-dev-alerts"
  }

  expect_failures = [var.alert_topic_arn]
}

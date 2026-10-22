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
      region = "us-east-1"
    }
  }

  # The mock returns random strings for computed attributes, which the role, role policy and bucket policy reject as
  # invalid JSON. The invariants are asserted on the document arguments (known at plan), not on the JSON.
  override_data {
    target = data.aws_iam_policy_document.bucket
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.trail_assume
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.trail_logs
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # Computed attributes are unknown at plan time; other resources and policy documents reference them.
  override_resource {
    target = aws_s3_bucket.logs
    values = {
      id  = "sc-dev-security-logs-123456789012"
      arn = "arn:aws:s3:::sc-dev-security-logs-123456789012"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.trail
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/cloudtrail/sc-dev-trail"
    }
  }

  override_resource {
    target = aws_iam_role.trail
    values = {
      id  = "sc-dev-cloudtrail-logs"
      arn = "arn:aws:iam::123456789012:role/sc-dev-cloudtrail-logs"
    }
  }
}

# Every service is enabled by default in this file; the runs switch services off one at a time.
variables {
  name_prefix = "sc-dev"

  enable_cloudtrail                     = true
  enable_guardduty                      = true
  enable_guardduty_s3_protection        = true
  enable_guardduty_malware_protection   = true
  enable_securityhub                    = true
  enable_config                         = true
  enable_config_service_linked_role     = true
  enable_access_analyzer                = true
  enable_s3_account_public_access_block = true
  enable_ebs_default_encryption         = true
  enable_iam_password_policy            = true

  # Documentation account ID and placeholder identifiers.
  kms_key_arn                   = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  permissions_boundary_arn      = "arn:aws:iam::123456789012:policy/sc-dev-workload-boundary"
  cloudwatch_log_retention_days = 14
}

# EN15-AC1: with every switch off, nothing is created
run "en15_ac1_all_disabled_creates_nothing" {
  command = plan

  variables {
    enable_cloudtrail                     = false
    enable_guardduty                      = false
    enable_guardduty_s3_protection        = false
    enable_guardduty_malware_protection   = false
    enable_securityhub                    = false
    enable_config                         = false
    enable_access_analyzer                = false
    enable_s3_account_public_access_block = false
    enable_ebs_default_encryption         = false
    enable_iam_password_policy            = false
    kms_key_arn                           = null
    permissions_boundary_arn              = null
    cloudwatch_log_retention_days         = null
  }

  assert {
    condition = alltrue([
      length(aws_cloudtrail.this) == 0,
      length(aws_cloudwatch_log_group.trail) == 0,
      length(aws_iam_role.trail) == 0,
      length(aws_iam_role_policy.trail) == 0,
      length(aws_s3_bucket.logs) == 0,
      length(aws_s3_bucket_policy.logs) == 0,
      length(aws_guardduty_detector.this) == 0,
      length(aws_guardduty_detector_feature.s3_data_events) == 0,
      length(aws_guardduty_detector_feature.ebs_malware_protection) == 0,
      length(aws_securityhub_account.this) == 0,
      length(aws_securityhub_standards_subscription.fsbp) == 0,
      length(aws_iam_service_linked_role.config) == 0,
      length(aws_config_configuration_recorder.this) == 0,
      length(aws_config_delivery_channel.this) == 0,
      length(aws_config_configuration_recorder_status.this) == 0,
      length(aws_accessanalyzer_analyzer.this) == 0,
      length(aws_s3_account_public_access_block.this) == 0,
      length(aws_ebs_encryption_by_default.this) == 0,
      length(aws_iam_account_password_policy.this) == 0,
    ])
    error_message = "No resource may be created when every switch is false."
  }
}

# EN15-AC1: enable_cloudtrail = false removes the trail and its integration, not the other services
run "en15_ac1_cloudtrail_disabled" {
  command = plan

  variables {
    enable_cloudtrail = false
  }

  assert {
    condition = alltrue([
      length(aws_cloudtrail.this) == 0,
      length(aws_cloudwatch_log_group.trail) == 0,
      length(aws_iam_role.trail) == 0,
      length(aws_iam_role_policy.trail) == 0,
    ])
    error_message = "The trail, its log group and its role must not exist when enable_cloudtrail is false."
  }

  assert {
    condition     = length(aws_config_configuration_recorder.this) == 1 && length(aws_guardduty_detector.this) == 1 && length(aws_securityhub_account.this) == 1 && length(aws_accessanalyzer_analyzer.this) == 1
    error_message = "The other services must be unaffected."
  }
}

# EN15-AC1: enable_guardduty = false removes the detector (and its features)
run "en15_ac1_guardduty_disabled" {
  command = plan

  variables {
    enable_guardduty                    = false
    enable_guardduty_s3_protection      = false
    enable_guardduty_malware_protection = false
  }

  assert {
    condition = alltrue([
      length(aws_guardduty_detector.this) == 0,
      length(aws_guardduty_detector_feature.s3_data_events) == 0,
      length(aws_guardduty_detector_feature.ebs_malware_protection) == 0,
    ])
    error_message = "The detector and its features must not exist when enable_guardduty is false."
  }

  assert {
    condition     = length(aws_cloudtrail.this) == 1 && length(aws_securityhub_account.this) == 1
    error_message = "The other services must be unaffected."
  }
}

# EN15-AC1: enable_securityhub = false removes Security Hub and the FSBP subscription
run "en15_ac1_securityhub_disabled" {
  command = plan

  variables {
    enable_securityhub = false
  }

  assert {
    condition     = length(aws_securityhub_account.this) == 0 && length(aws_securityhub_standards_subscription.fsbp) == 0
    error_message = "Security Hub must not exist when enable_securityhub is false."
  }

  assert {
    condition     = length(aws_cloudtrail.this) == 1 && length(aws_guardduty_detector.this) == 1
    error_message = "The other services must be unaffected."
  }
}

# EN15-AC1: enable_config = false removes the recorder; the bucket stays for the trail
run "en15_ac1_config_disabled" {
  command = plan

  variables {
    enable_config = false
  }

  assert {
    condition = alltrue([
      length(aws_config_configuration_recorder.this) == 0,
      length(aws_config_delivery_channel.this) == 0,
      length(aws_config_configuration_recorder_status.this) == 0,
      length(aws_iam_service_linked_role.config) == 0,
    ])
    error_message = "The Config recorder, delivery channel and service-linked role must not exist when enable_config is false."
  }

  assert {
    condition     = length(aws_s3_bucket.logs) == 1 && length(aws_cloudtrail.this) == 1
    error_message = "The log bucket must remain for the trail."
  }
}

# EN15-AC1: enable_access_analyzer = false removes the analyzer
run "en15_ac1_access_analyzer_disabled" {
  command = plan

  variables {
    enable_access_analyzer = false
  }

  assert {
    condition     = length(aws_accessanalyzer_analyzer.this) == 0
    error_message = "The analyzer must not exist when enable_access_analyzer is false."
  }

  assert {
    condition     = length(aws_cloudtrail.this) == 1 && length(aws_config_configuration_recorder.this) == 1
    error_message = "The other services must be unaffected."
  }
}

# EN15-AC1: the log bucket exists only when the trail or Config needs it
run "en15_ac1_log_bucket_only_when_needed" {
  command = plan

  variables {
    enable_cloudtrail             = false
    enable_config                 = false
    permissions_boundary_arn      = null
    cloudwatch_log_retention_days = null
  }

  assert {
    condition     = length(aws_s3_bucket.logs) == 0 && length(aws_s3_bucket_policy.logs) == 0
    error_message = "The log bucket must not be created when neither CloudTrail nor Config is enabled."
  }
}

# EN15-AC1: rejects the GuardDuty features without the detector
run "en15_ac1_rejects_guardduty_s3_protection_without_detector" {
  command = plan

  variables {
    enable_guardduty = false
  }

  expect_failures = [var.enable_guardduty_s3_protection, var.enable_guardduty_malware_protection]
}

# EN15-AC1: rejects an invalid name_prefix
run "en15_ac1_rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Bad_Prefix"
  }

  expect_failures = [var.name_prefix]
}

# EN15-AC2: the trail is multi-region, validates log files, is encrypted and delivers to the log bucket
run "en15_ac2_trail_multi_region_with_validation" {
  command = plan

  variables {
    tags = { Owner = "ops" }
  }

  assert {
    condition     = aws_cloudtrail.this[0].name == "sc-dev-trail"
    error_message = "The trail name must be <prefix>-trail."
  }

  assert {
    condition     = aws_cloudtrail.this[0].is_multi_region_trail == true
    error_message = "The trail must be multi-region."
  }

  assert {
    condition     = aws_cloudtrail.this[0].enable_log_file_validation == true
    error_message = "Log file validation must be enabled."
  }

  assert {
    condition     = aws_cloudtrail.this[0].include_global_service_events == true
    error_message = "The trail must record global service events."
  }

  assert {
    condition     = aws_cloudtrail.this[0].kms_key_id == var.kms_key_arn
    error_message = "The trail must be encrypted with the logs KMS key."
  }

  assert {
    condition     = aws_cloudtrail.this[0].s3_bucket_name == "sc-dev-security-logs-123456789012" && aws_cloudtrail.this[0].s3_key_prefix == "cloudtrail"
    error_message = "The trail must deliver to the security log bucket under the cloudtrail prefix."
  }

  assert {
    condition     = aws_cloudtrail.this[0].tags["Owner"] == "ops"
    error_message = "Extra tags must be applied to the trail."
  }
}

# EN15-AC2: the log bucket blocks public access, enforces ownership, is versioned and has a lifecycle
run "en15_ac2_log_bucket_private_and_versioned" {
  command = plan

  variables {
    log_bucket_expiration_days                    = 400
    log_bucket_noncurrent_version_expiration_days = 30
    abort_incomplete_multipart_upload_days        = 3
  }

  assert {
    condition     = aws_s3_bucket.logs[0].bucket == "sc-dev-security-logs-123456789012" && aws_s3_bucket.logs[0].force_destroy == false
    error_message = "The bucket name must be <prefix>-security-logs-<account id> and the bucket must never be force-destroyed."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.logs[0].block_public_acls,
      aws_s3_bucket_public_access_block.logs[0].block_public_policy,
      aws_s3_bucket_public_access_block.logs[0].ignore_public_acls,
      aws_s3_bucket_public_access_block.logs[0].restrict_public_buckets,
    ])
    error_message = "Block Public Access must be fully enabled on the log bucket."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.logs[0].rule).object_ownership == "BucketOwnerEnforced"
    error_message = "Object ownership must be BucketOwnerEnforced."
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.logs[0].versioning_configuration).status == "Enabled"
    error_message = "Versioning must be enabled on the log bucket."
  }

  assert {
    condition = one([
      for r in aws_s3_bucket_lifecycle_configuration.logs[0].rule : r if r.id == "expire-logs"
    ]).status == "Enabled"
    error_message = "The log expiration rule must be enabled."
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.logs[0].rule : r if r.id == "expire-logs"
    ]).expiration).days == 400
    error_message = "Logs must expire after log_bucket_expiration_days."
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.logs[0].rule : r if r.id == "expire-logs"
    ]).noncurrent_version_expiration).noncurrent_days == 30
    error_message = "Noncurrent versions must expire after log_bucket_noncurrent_version_expiration_days."
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.logs[0].rule : r if r.id == "abort-incomplete-multipart-uploads"
    ]).abort_incomplete_multipart_upload).days_after_initiation == 3
    error_message = "Incomplete multipart uploads must be aborted after the configured days."
  }
}

# EN15-AC2: the log bucket is encrypted with the logs KMS key and a bucket key
run "en15_ac2_log_bucket_encrypted_with_logs_key" {
  command = plan

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.logs[0].rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "Default encryption must be aws:kms."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.logs[0].rule).apply_server_side_encryption_by_default).kms_master_key_id == var.kms_key_arn
    error_message = "Default encryption must use the logs KMS key."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.logs[0].rule).bucket_key_enabled == true
    error_message = "S3 Bucket Keys must be enabled."
  }
}

# EN15-AC2: the bucket policy denies non-TLS access
run "en15_ac2_bucket_policy_tls_only" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket[0].statement :
      s.sid == "DenyInsecureTransport" && s.effect == "Deny" &&
      toset(s.resources) == toset(["arn:aws:s3:::sc-dev-security-logs-123456789012", "arn:aws:s3:::sc-dev-security-logs-123456789012/*"]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SecureTransport" && c.test == "Bool" && contains(c.values, "false")
      ])
    ])
    error_message = "The bucket policy must deny requests without aws:SecureTransport."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket[0].statement :
      s.sid == "DenyOutdatedTls" && s.effect == "Deny" && anytrue([
        for c in s.condition :
        c.variable == "s3:TlsVersion" && c.test == "NumericLessThan" && contains(c.values, "1.2")
      ])
    ])
    error_message = "The bucket policy must deny TLS versions below 1.2."
  }
}

# EN15-AC2: CloudTrail may only write on behalf of this trail (confused deputy)
run "en15_ac2_bucket_policy_cloudtrail_source_arn" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket[0].statement :
      s.sid == "CloudTrailAclCheck" && s.effect == "Allow" && toset(s.actions) == toset(["s3:GetBucketAcl"]) &&
      toset(s.resources) == toset(["arn:aws:s3:::sc-dev-security-logs-123456789012"]) &&
      alltrue([for p in s.principals : p.type == "Service" && p.identifiers == toset(["cloudtrail.amazonaws.com"])]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceArn" && c.test == "StringEquals" && toset(c.values) == toset(["arn:aws:cloudtrail:us-east-1:123456789012:trail/sc-dev-trail"])
      ]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceAccount" && c.test == "StringEquals" && toset(c.values) == toset(["123456789012"])
      ])
    ])
    error_message = "CloudTrailAclCheck must be limited to cloudtrail.amazonaws.com with aws:SourceArn set to the trail and aws:SourceAccount set to this account."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket[0].statement :
      s.sid == "CloudTrailWrite" && s.effect == "Allow" && toset(s.actions) == toset(["s3:PutObject"]) &&
      toset(s.resources) == toset(["arn:aws:s3:::sc-dev-security-logs-123456789012/cloudtrail/AWSLogs/123456789012/*"]) &&
      alltrue([for p in s.principals : p.type == "Service" && p.identifiers == toset(["cloudtrail.amazonaws.com"])]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceArn" && c.test == "StringEquals" && toset(c.values) == toset(["arn:aws:cloudtrail:us-east-1:123456789012:trail/sc-dev-trail"])
      ]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceAccount" && c.test == "StringEquals" && toset(c.values) == toset(["123456789012"])
      ]) &&
      anytrue([
        for c in s.condition :
        c.variable == "s3:x-amz-acl" && c.test == "StringEquals" && toset(c.values) == toset(["bucket-owner-full-control"])
      ])
    ])
    error_message = "CloudTrailWrite must be limited to the trail prefix, the trail source ARN, this account and bucket-owner-full-control."
  }
}

# EN15-AC2: no Allow statement of the bucket policy uses a wildcard principal or action
run "en15_ac2_bucket_policy_no_wildcard_allow" {
  command = plan

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.bucket[0].statement :
      alltrue([for p in s.principals : p.type != "*" && !contains(p.identifiers, "*")])
      if s.effect == "Allow"
    ])
    error_message = "No Allow statement may use a \"*\" principal."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.bucket[0].statement :
      !anytrue([for a in s.actions : a == "*" || endswith(a, ":*")])
      if s.effect == "Allow"
    ])
    error_message = "No Allow statement may use a wildcard action."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.bucket[0].statement :
      length(s.condition) > 0
      if s.effect == "Allow"
    ])
    error_message = "Every Allow statement for a service principal must carry a condition."
  }
}

# EN15-AC2: the CloudWatch log group of the trail is KMS-encrypted with a retention
run "en15_ac2_trail_log_group_encrypted_with_retention" {
  command = plan

  variables {
    cloudwatch_log_retention_days = 90
  }

  assert {
    condition     = aws_cloudwatch_log_group.trail[0].name == "/aws/cloudtrail/sc-dev-trail"
    error_message = "The log group name must follow the trail name."
  }

  assert {
    condition     = aws_cloudwatch_log_group.trail[0].kms_key_id == var.kms_key_arn
    error_message = "The trail log group must be encrypted with the logs KMS key."
  }

  assert {
    condition     = aws_cloudwatch_log_group.trail[0].retention_in_days == 90
    error_message = "The trail log group retention must follow cloudwatch_log_retention_days."
  }
}

# EN15-AC2: the CloudWatch Logs role carries the boundary, a pinned trust and a scoped policy
run "en15_ac2_trail_role_boundary_and_least_privilege" {
  command = plan

  assert {
    condition     = aws_iam_role.trail[0].permissions_boundary == var.permissions_boundary_arn
    error_message = "The CloudTrail role must carry the project permissions boundary."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.trail_assume[0].statement :
      s.effect == "Allow" && toset(s.actions) == toset(["sts:AssumeRole"]) &&
      alltrue([for p in s.principals : p.type == "Service" && p.identifiers == toset(["cloudtrail.amazonaws.com"])]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceArn" && c.test == "StringEquals" && toset(c.values) == toset(["arn:aws:cloudtrail:us-east-1:123456789012:trail/sc-dev-trail"])
      ]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceAccount" && c.test == "StringEquals" && toset(c.values) == toset(["123456789012"])
      ])
    ])
    error_message = "The trust policy must name cloudtrail.amazonaws.com with aws:SourceArn and aws:SourceAccount conditions."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.trail_logs[0].statement :
      toset(s.actions) == toset(["logs:CreateLogStream", "logs:PutLogEvents"]) &&
      toset(s.resources) == toset(["arn:aws:logs:us-east-1:123456789012:log-group:/aws/cloudtrail/sc-dev-trail:log-stream:*"])
    ])
    error_message = "The role policy must only write log streams of the trail log group."
  }

  assert {
    condition     = aws_cloudtrail.this[0].cloud_watch_logs_group_arn == "arn:aws:logs:us-east-1:123456789012:log-group:/aws/cloudtrail/sc-dev-trail:*"
    error_message = "The trail must deliver to its CloudWatch log group."
  }
}

# EN15-AC2: Config alone still gets a private log bucket, without any CloudTrail statement
run "en15_ac2_config_only_bucket_has_no_trail_statements" {
  command = plan

  variables {
    enable_cloudtrail             = false
    permissions_boundary_arn      = null
    cloudwatch_log_retention_days = null
  }

  assert {
    condition     = length(aws_s3_bucket.logs) == 1 && length(aws_s3_bucket_policy.logs) == 1
    error_message = "Config needs the log bucket."
  }

  assert {
    condition     = !anytrue([for s in data.aws_iam_policy_document.bucket[0].statement : startswith(s.sid, "CloudTrail")])
    error_message = "The bucket policy must not allow CloudTrail when the trail is disabled."
  }
}

# EN15-AC2: rejects the trail without a KMS key
run "en15_ac2_rejects_cloudtrail_without_kms_key" {
  command = plan

  variables {
    kms_key_arn = null
  }

  expect_failures = [var.kms_key_arn]
}

# EN15-AC2: rejects Config without a KMS key
run "en15_ac2_rejects_config_without_kms_key" {
  command = plan

  variables {
    enable_cloudtrail             = false
    permissions_boundary_arn      = null
    cloudwatch_log_retention_days = null
    kms_key_arn                   = null
  }

  expect_failures = [var.kms_key_arn]
}

# EN15-AC2: rejects a KMS alias in place of a key ARN
run "en15_ac2_rejects_kms_alias_arn" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:alias/sc-dev-logs"
  }

  expect_failures = [var.kms_key_arn]
}

# EN15-AC2: rejects the trail without a permissions boundary
run "en15_ac2_rejects_cloudtrail_without_permissions_boundary" {
  command = plan

  variables {
    permissions_boundary_arn = null
  }

  expect_failures = [var.permissions_boundary_arn]
}

# EN15-AC2: rejects a permissions boundary that is not a policy ARN
run "en15_ac2_rejects_invalid_permissions_boundary" {
  command = plan

  variables {
    permissions_boundary_arn = "sc-dev-workload-boundary"
  }

  expect_failures = [var.permissions_boundary_arn]
}

# EN15-AC2: rejects the trail without a log group retention
run "en15_ac2_rejects_cloudtrail_without_log_retention" {
  command = plan

  variables {
    cloudwatch_log_retention_days = null
  }

  expect_failures = [var.cloudwatch_log_retention_days]
}

# EN15-AC2: rejects a retention value CloudWatch Logs does not support
run "en15_ac2_rejects_unsupported_log_retention" {
  command = plan

  variables {
    cloudwatch_log_retention_days = 10
  }

  expect_failures = [var.cloudwatch_log_retention_days]
}

# EN15-AC2: rejects a log bucket expiration below 1 day
run "en15_ac2_rejects_expiration_days_below_1" {
  command = plan

  variables {
    log_bucket_expiration_days = 0
  }

  expect_failures = [var.log_bucket_expiration_days]
}

# EN15-AC2: rejects a noncurrent version expiration below 1 day
run "en15_ac2_rejects_noncurrent_days_below_1" {
  command = plan

  variables {
    log_bucket_noncurrent_version_expiration_days = 0
  }

  expect_failures = [var.log_bucket_noncurrent_version_expiration_days]
}

# EN15-AC2: rejects an abort multipart delay below 1 day
run "en15_ac2_rejects_multipart_days_below_1" {
  command = plan

  variables {
    abort_incomplete_multipart_upload_days = 0
  }

  expect_failures = [var.abort_incomplete_multipart_upload_days]
}

# EN15-AC3: Security Hub is enabled with the AWS Foundational Security Best Practices standard
run "en15_ac3_securityhub_fsbp_subscribed" {
  command = plan

  assert {
    condition     = aws_securityhub_standards_subscription.fsbp[0].standards_arn == "arn:aws:securityhub:us-east-1::standards/aws-foundational-security-best-practices/v/1.0.0"
    error_message = "The FSBP standard must be subscribed."
  }

  assert {
    condition     = aws_securityhub_account.this[0].enable_default_standards == false
    error_message = "Standards must be subscribed explicitly, not through the default set."
  }

  assert {
    condition     = aws_securityhub_account.this[0].auto_enable_controls == true && aws_securityhub_account.this[0].control_finding_generator == "SECURITY_CONTROL"
    error_message = "New controls must be enabled automatically with consolidated control findings."
  }
}

# EN15-AC4: GuardDuty detector is enabled with the S3 and malware features
run "en15_ac4_guardduty_detector_with_features" {
  command = plan

  assert {
    condition     = aws_guardduty_detector.this[0].enable == true
    error_message = "The GuardDuty detector must be enabled."
  }

  assert {
    condition     = aws_guardduty_detector.this[0].finding_publishing_frequency == "FIFTEEN_MINUTES"
    error_message = "GuardDuty findings must be published every 15 minutes."
  }

  assert {
    condition     = aws_guardduty_detector_feature.s3_data_events[0].name == "S3_DATA_EVENTS" && aws_guardduty_detector_feature.s3_data_events[0].status == "ENABLED"
    error_message = "The S3 data events feature must be enabled."
  }

  assert {
    condition     = aws_guardduty_detector_feature.ebs_malware_protection[0].name == "EBS_MALWARE_PROTECTION" && aws_guardduty_detector_feature.ebs_malware_protection[0].status == "ENABLED"
    error_message = "The EBS malware protection feature must be enabled."
  }
}

# EN15-AC4: the GuardDuty features follow their own switches
run "en15_ac4_guardduty_features_off" {
  command = plan

  variables {
    enable_guardduty_s3_protection      = false
    enable_guardduty_malware_protection = false
  }

  assert {
    condition     = length(aws_guardduty_detector.this) == 1
    error_message = "The detector must still be created."
  }

  assert {
    condition     = length(aws_guardduty_detector_feature.s3_data_events) == 0 && length(aws_guardduty_detector_feature.ebs_malware_protection) == 0
    error_message = "The features must not be created when their switches are false."
  }
}

# EN15-AC4: Config records every supported resource and delivers to the trail bucket under its own prefix
run "en15_ac4_config_recorder_and_delivery" {
  command = plan

  assert {
    condition     = aws_config_configuration_recorder.this[0].role_arn == "arn:aws:iam::123456789012:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
    error_message = "The recorder must use the AWS Config service-linked role."
  }

  assert {
    condition     = one(aws_config_configuration_recorder.this[0].recording_group).all_supported == true && one(aws_config_configuration_recorder.this[0].recording_group).include_global_resource_types == true
    error_message = "The recorder must record all supported resource types, including global ones."
  }

  assert {
    condition     = aws_config_delivery_channel.this[0].s3_bucket_name == "sc-dev-security-logs-123456789012" && aws_config_delivery_channel.this[0].s3_key_prefix == "config"
    error_message = "Config must deliver to the security log bucket under the config prefix."
  }

  assert {
    condition     = aws_config_delivery_channel.this[0].s3_kms_key_arn == var.kms_key_arn
    error_message = "Config deliveries must name the logs KMS key."
  }

  assert {
    condition     = aws_config_configuration_recorder_status.this[0].is_enabled == true
    error_message = "The recorder must be started."
  }

  assert {
    condition     = length(aws_iam_service_linked_role.config) == 1 && aws_iam_service_linked_role.config[0].aws_service_name == "config.amazonaws.com"
    error_message = "The Config service-linked role must be created when enable_config_service_linked_role is true."
  }
}

# EN15-AC4: the Config service-linked role is skipped when it already exists
run "en15_ac4_config_service_linked_role_skipped" {
  command = plan

  variables {
    enable_config_service_linked_role = false
  }

  assert {
    condition     = length(aws_iam_service_linked_role.config) == 0 && length(aws_config_configuration_recorder.this) == 1
    error_message = "The service-linked role must not be created, the recorder must remain."
  }
}

# EN15-AC4: Config may only write to its own prefix, on behalf of this account and the recorder (confused deputy)
run "en15_ac4_bucket_policy_config_source_arn" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket[0].statement :
      s.sid == "ConfigBucketCheck" && s.effect == "Allow" && toset(s.actions) == toset(["s3:GetBucketAcl", "s3:ListBucket"]) &&
      toset(s.resources) == toset(["arn:aws:s3:::sc-dev-security-logs-123456789012"]) &&
      alltrue([for p in s.principals : p.type == "Service" && p.identifiers == toset(["config.amazonaws.com"])]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceArn" && c.test == "StringEquals" && toset(c.values) == toset(["arn:aws:config:us-east-1:123456789012:config-recorder/sc-dev-config"])
      ]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceAccount" && c.test == "StringEquals" && toset(c.values) == toset(["123456789012"])
      ])
    ])
    error_message = "ConfigBucketCheck must be limited to config.amazonaws.com with aws:SourceArn set to the recorder and aws:SourceAccount set to this account."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket[0].statement :
      s.sid == "ConfigWrite" && s.effect == "Allow" && toset(s.actions) == toset(["s3:PutObject"]) &&
      toset(s.resources) == toset(["arn:aws:s3:::sc-dev-security-logs-123456789012/config/AWSLogs/123456789012/Config/*"]) &&
      alltrue([for p in s.principals : p.type == "Service" && p.identifiers == toset(["config.amazonaws.com"])]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceArn" && c.test == "StringEquals" && toset(c.values) == toset(["arn:aws:config:us-east-1:123456789012:config-recorder/sc-dev-config"])
      ]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceAccount" && c.test == "StringEquals" && toset(c.values) == toset(["123456789012"])
      ]) &&
      anytrue([
        for c in s.condition :
        c.variable == "s3:x-amz-acl" && c.test == "StringEquals" && toset(c.values) == toset(["bucket-owner-full-control"])
      ])
    ])
    error_message = "ConfigWrite must be limited to the Config prefix, the recorder source ARN, this account and bucket-owner-full-control."
  }
}

# EN15-AC4: the account-level IAM Access Analyzer is created
run "en15_ac4_access_analyzer_account_type" {
  command = plan

  assert {
    condition     = aws_accessanalyzer_analyzer.this[0].type == "ACCOUNT" && aws_accessanalyzer_analyzer.this[0].analyzer_name == "sc-dev-account"
    error_message = "The analyzer must be an account analyzer named <prefix>-account."
  }
}

# EN15-AC1: account hardening settings are strict when enabled
run "en15_ac1_account_hardening_settings" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_account_public_access_block.this[0].block_public_acls,
      aws_s3_account_public_access_block.this[0].block_public_policy,
      aws_s3_account_public_access_block.this[0].ignore_public_acls,
      aws_s3_account_public_access_block.this[0].restrict_public_buckets,
    ])
    error_message = "Account-level Block Public Access must be fully enabled."
  }

  assert {
    condition     = aws_ebs_encryption_by_default.this[0].enabled == true
    error_message = "EBS encryption by default must be enabled."
  }

  assert {
    condition = alltrue([
      aws_iam_account_password_policy.this[0].minimum_password_length >= 14,
      aws_iam_account_password_policy.this[0].require_lowercase_characters,
      aws_iam_account_password_policy.this[0].require_uppercase_characters,
      aws_iam_account_password_policy.this[0].require_numbers,
      aws_iam_account_password_policy.this[0].require_symbols,
      aws_iam_account_password_policy.this[0].max_password_age <= 90,
      aws_iam_account_password_policy.this[0].password_reuse_prevention >= 24,
    ])
    error_message = "The password policy must require 14+ characters, every class, 90-day expiry and 24 passwords of history."
  }
}

# EN15-AC1: account hardening resources follow their own switches
run "en15_ac1_account_hardening_disabled" {
  command = plan

  variables {
    enable_s3_account_public_access_block = false
    enable_ebs_default_encryption         = false
    enable_iam_password_policy            = false
  }

  assert {
    condition     = length(aws_s3_account_public_access_block.this) == 0 && length(aws_ebs_encryption_by_default.this) == 0 && length(aws_iam_account_password_policy.this) == 0
    error_message = "Account hardening resources must not be created when their switches are false."
  }
}

# EN15-AC2: objects can only be written with the logs KMS key
run "en15_ac2_bucket_policy_denies_other_kms_key" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket[0].statement :
      s.sid == "DenyWrongKmsKey" && s.effect == "Deny" && toset(s.actions) == toset(["s3:PutObject"]) &&
      toset(s.resources) == toset(["arn:aws:s3:::sc-dev-security-logs-123456789012/*"]) &&
      anytrue([
        for c in s.condition :
        c.variable == "s3:x-amz-server-side-encryption-aws-kms-key-id" && c.test == "StringNotEqualsIfExists" && toset(c.values) == toset([var.kms_key_arn])
      ])
    ])
    error_message = "The bucket policy must deny PutObject with a KMS key other than the logs key."
  }
}

# EN15-AC2: without the data events flag the trail keeps the default event selector
run "en15_ac2_trail_no_data_events_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudtrail.this[0].advanced_event_selector) == 0
    error_message = "No advanced event selector may be set when enable_cloudtrail_s3_data_events is false."
  }
}

# EN15-AC2: the data events flag records management events and S3 objects of the listed buckets only
run "en15_ac2_trail_s3_data_events" {
  command = plan

  variables {
    enable_cloudtrail_s3_data_events     = true
    cloudtrail_s3_data_event_bucket_arns = ["arn:aws:s3:::sc-dev-attachments", "arn:aws:s3:::sc-dev-tfstate"]
  }

  assert {
    condition = anytrue([
      for sel in aws_cloudtrail.this[0].advanced_event_selector :
      anytrue([for f in sel.field_selector : f.field == "eventCategory" && toset(f.equals) == toset(["Management"])])
    ])
    error_message = "Management events must stay recorded when advanced event selectors are used."
  }

  assert {
    condition = anytrue([
      for sel in aws_cloudtrail.this[0].advanced_event_selector :
      anytrue([for f in sel.field_selector : f.field == "eventCategory" && toset(f.equals) == toset(["Data"])]) &&
      anytrue([for f in sel.field_selector : f.field == "resources.type" && toset(f.equals) == toset(["AWS::S3::Object"])]) &&
      anytrue([
        for f in sel.field_selector :
        f.field == "resources.ARN" && toset(f.starts_with) == toset(["arn:aws:s3:::sc-dev-attachments/", "arn:aws:s3:::sc-dev-tfstate/"])
      ])
    ])
    error_message = "S3 object data events must be limited to the listed buckets."
  }
}

# EN15-AC2: rejects the data events flag without bucket ARNs
run "en15_ac2_rejects_data_events_without_buckets" {
  command = plan

  variables {
    enable_cloudtrail_s3_data_events = true
  }

  expect_failures = [var.enable_cloudtrail_s3_data_events]
}

# EN15-AC2: rejects the data events flag without the trail
run "en15_ac2_rejects_data_events_without_trail" {
  command = plan

  variables {
    enable_cloudtrail                    = false
    permissions_boundary_arn             = null
    cloudwatch_log_retention_days        = null
    enable_cloudtrail_s3_data_events     = true
    cloudtrail_s3_data_event_bucket_arns = ["arn:aws:s3:::sc-dev-attachments"]
  }

  expect_failures = [var.enable_cloudtrail_s3_data_events]
}

# EN15-AC2: rejects an object ARN in place of a bucket ARN
run "en15_ac2_rejects_data_events_object_arn" {
  command = plan

  variables {
    cloudtrail_s3_data_event_bucket_arns = ["arn:aws:s3:::sc-dev-attachments/uploads/*"]
  }

  expect_failures = [var.cloudtrail_s3_data_event_bucket_arns]
}

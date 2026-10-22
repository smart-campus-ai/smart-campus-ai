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

  # Computed attributes are unknown at plan time; the bucket policy and SSE configuration reference the key ARN.
  override_resource {
    target = aws_kms_key.this
    values = {
      arn    = "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000"
      key_id = "00000000-0000-0000-0000-000000000000"
    }
  }

  override_resource {
    target = aws_s3_bucket.state
    values = {
      id  = "sc-tfstate-123456789012"
      arn = "arn:aws:s3:::sc-tfstate-123456789012"
    }
  }

  # The mock returns random strings for computed attributes, which aws_kms_key.policy and aws_s3_bucket_policy.policy
  # reject as invalid JSON. The invariants are asserted on the document arguments (known at plan), not on the JSON.
  override_data {
    target = data.aws_iam_policy_document.key
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.bucket
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix = "sc"
  # Documentation account ID and placeholder role names.
  admin_principal_arns = [
    "arn:aws:iam::123456789012:role/sc-bootstrap-admin",
    "arn:aws:iam::123456789012:user/sc-break-glass",
  ]
}

# EN12-AC1: bucket blocks all public access and enforces bucket owner
run "en12_ac1_bucket_public_access_blocked" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets,
    ])
    error_message = "Block Public Access must be fully enabled on the state bucket."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.state.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "Object ownership must be BucketOwnerEnforced."
  }

  assert {
    condition     = aws_s3_bucket.state.bucket == "sc-tfstate-123456789012"
    error_message = "Bucket name must be <prefix>-tfstate-<account id>."
  }

  assert {
    condition     = aws_s3_bucket.state.force_destroy == false
    error_message = "The state bucket must never be force-destroyed."
  }
}

# EN12-AC1: bucket versioning is enabled
run "en12_ac1_bucket_versioning_enabled" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_versioning.state.versioning_configuration).status == "Enabled"
    error_message = "Versioning must be enabled on the state bucket."
  }
}

# EN12-AC1: default encryption is SSE-KMS with the state key and bucket key
run "en12_ac1_default_encryption_sse_kms" {
  command = plan

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "Default encryption must be aws:kms."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default).kms_master_key_id == aws_kms_key.this.arn
    error_message = "Default encryption must use the state KMS key."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.state.rule).bucket_key_enabled == true
    error_message = "S3 Bucket Keys must be enabled."
  }
}

# EN12-AC1: bucket policy denies insecure transport and unencrypted or other-key puts
run "en12_ac1_bucket_policy_denies_insecure_access" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket.statement :
      s.sid == "DenyInsecureTransport" && s.effect == "Deny" && anytrue([
        for c in s.condition :
        c.variable == "aws:SecureTransport" && c.test == "Bool" && contains(c.values, "false")
      ])
    ])
    error_message = "The bucket policy must deny requests without aws:SecureTransport."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket.statement :
      s.sid == "DenyOutdatedTls" && s.effect == "Deny" && anytrue([
        for c in s.condition :
        c.variable == "s3:TlsVersion" && c.test == "NumericLessThan" && contains(c.values, "1.2")
      ])
    ])
    error_message = "The bucket policy must deny TLS versions below 1.2."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket.statement :
      s.sid == "DenyNonKmsEncryptionHeader" && s.effect == "Deny" && contains(s.actions, "s3:PutObject") && anytrue([
        for c in s.condition :
        c.variable == "s3:x-amz-server-side-encryption" && c.test == "StringNotEqualsIfExists" && contains(c.values, "aws:kms")
      ])
    ])
    error_message = "The bucket policy must deny puts that are not SSE-KMS."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket.statement :
      s.sid == "DenyOtherKmsKey" && s.effect == "Deny" && contains(s.actions, "s3:PutObject") && anytrue([
        for c in s.condition :
        c.variable == "s3:x-amz-server-side-encryption-aws-kms-key-id" && c.test == "StringNotEqualsIfExists" && contains(c.values, "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000")
      ])
    ])
    error_message = "The bucket policy must deny puts encrypted with another KMS key."
  }

  assert {
    condition     = alltrue([for s in data.aws_iam_policy_document.bucket.statement : s.effect == "Deny"])
    error_message = "The bucket policy must only contain Deny statements; access is granted by IAM."
  }
}

# EN12-AC1: access logging is off by default
run "en12_ac1_access_logging_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_logging.state) == 0
    error_message = "Access logging must be disabled unless requested."
  }
}

# EN12-AC1: access logging targets the given bucket when enabled
run "en12_ac1_access_logging_targets_given_bucket" {
  command = plan

  variables {
    enable_access_logging  = true
    access_log_bucket_name = "sc-access-logs"
  }

  assert {
    condition     = one(aws_s3_bucket_logging.state).target_bucket == "sc-access-logs"
    error_message = "Access logs must be delivered to access_log_bucket_name."
  }
}

# EN12-AC2: key rotation is enabled and deletion window is configurable
run "en12_ac2_key_rotation_enabled" {
  command = plan

  variables {
    kms_deletion_window_in_days = 14
  }

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true
    error_message = "KMS key rotation must be enabled."
  }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 14
    error_message = "The KMS deletion window must follow the variable."
  }

  assert {
    condition     = aws_kms_key.this.key_usage == "ENCRYPT_DECRYPT" && aws_kms_key.this.customer_master_key_spec == "SYMMETRIC_DEFAULT"
    error_message = "The state key must be a symmetric encrypt/decrypt key."
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/sc-tfstate"
    error_message = "The key alias must be alias/<prefix>-tfstate."
  }
}

# EN12-AC2: key policy is explicit and has no "*" principal
run "en12_ac2_key_policy_no_wildcard_principal" {
  command = plan

  assert {
    condition     = length(data.aws_iam_policy_document.key.statement) > 0
    error_message = "The key policy must contain explicit statements."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.key.statement :
      alltrue([for p in s.principals : p.type != "*" && !contains(p.identifiers, "*")])
    ])
    error_message = "The key policy must not contain a \"*\" principal."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.key.statement :
      !anytrue([for a in s.actions : a == "*" || a == "kms:*"])
    ])
    error_message = "The key policy must list explicit KMS actions."
  }
}

# EN12-AC2: the account root delegates usage to IAM and cannot schedule deletion or disable the key
run "en12_ac2_root_statements_cannot_destroy_key" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.key.statement :
      s.sid == "EnableIamDelegation" && s.effect == "Allow" &&
      alltrue([for p in s.principals : p.type == "AWS" && p.identifiers == toset(["arn:aws:iam::123456789012:root"])]) &&
      toset(s.actions) == toset([
        "kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext",
        "kms:ReEncryptFrom", "kms:ReEncryptTo",
      ])
    ])
    error_message = "EnableIamDelegation must grant the account root usage actions only."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.key.statement :
      s.sid == "RootLockoutRecovery" && toset(s.actions) == toset(["kms:DescribeKey", "kms:GetKeyPolicy", "kms:PutKeyPolicy"])
    ])
    error_message = "The account root must keep exactly DescribeKey, GetKeyPolicy and PutKeyPolicy for lockout recovery."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.key.statement :
      !anytrue([for a in s.actions : contains(["kms:ScheduleKeyDeletion", "kms:DisableKey"], a)])
      if anytrue([for p in s.principals : anytrue([for i in p.identifiers : endswith(i, ":root")])])
    ])
    error_message = "No statement granted to the account root may include ScheduleKeyDeletion or DisableKey."
  }
}

# EN12-AC2: only the admin principals administer the key
run "en12_ac2_admin_statement_uses_admin_principals" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.key.statement :
      s.sid == "KeyAdministration" && s.effect == "Allow" &&
      alltrue([for p in s.principals : p.type == "AWS" && p.identifiers == toset(var.admin_principal_arns)]) &&
      contains(s.actions, "kms:ScheduleKeyDeletion") && contains(s.actions, "kms:DisableKey") && contains(s.actions, "kms:PutKeyPolicy")
    ])
    error_message = "KeyAdministration must be granted to exactly admin_principal_arns."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.key.statement :
      anytrue([for a in s.actions : a == "kms:ScheduleKeyDeletion"]) ? s.sid == "KeyAdministration" : true
    ])
    error_message = "Only KeyAdministration may schedule key deletion."
  }
}

# EN12-AC2: SSE-C writes are denied
run "en12_ac2_bucket_policy_denies_sse_c" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket.statement :
      s.sid == "DenySSEC" && s.effect == "Deny" && toset(s.actions) == toset(["s3:PutObject"]) && anytrue([
        for c in s.condition :
        c.variable == "s3:x-amz-server-side-encryption-customer-algorithm" && c.test == "Null" && toset(c.values) == toset(["false"])
      ])
    ])
    error_message = "The bucket policy must deny PutObject when an SSE-C algorithm header is present."
  }
}

# EN12-AC5: the recovery path is protected from everyone but the admin principals
run "en12_ac5_bucket_policy_protects_recovery_path" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket.statement :
      s.sid == "DenyRecoveryTampering" && s.effect == "Deny" &&
      toset(s.actions) == toset([
        "s3:DeleteBucketPolicy", "s3:DeleteObjectVersion", "s3:PutBucketPolicy", "s3:PutBucketVersioning", "s3:PutLifecycleConfiguration",
      ]) &&
      toset(s.resources) == toset(["arn:aws:s3:::sc-tfstate-123456789012", "arn:aws:s3:::sc-tfstate-123456789012/*"]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:PrincipalArn" && c.test == "ArnNotEquals" && toset(c.values) == toset(var.admin_principal_arns)
      ])
    ])
    error_message = "DenyRecoveryTampering must deny recovery-path changes unless aws:PrincipalArn is an admin principal."
  }
}

# EN12-AC2: rejects an empty admin principal list
run "en12_ac2_rejects_empty_admin_principal_arns" {
  command = plan

  variables {
    admin_principal_arns = []
  }

  expect_failures = [var.admin_principal_arns]
}

# EN12-AC2: rejects a value that is not an IAM role or user ARN
run "en12_ac2_rejects_non_arn_admin_principal" {
  command = plan

  variables {
    admin_principal_arns = ["sc-bootstrap-admin"]
  }

  expect_failures = [var.admin_principal_arns]
}

# EN12-AC2: rejects the account root and wildcards as admin principals
run "en12_ac2_rejects_root_and_wildcard_admin_principal" {
  command = plan

  variables {
    admin_principal_arns = ["arn:aws:iam::123456789012:root", "arn:aws:iam::123456789012:role/*"]
  }

  expect_failures = [var.admin_principal_arns]
}

# EN12-AC5: noncurrent versions expire after the configured duration
run "en12_ac5_noncurrent_versions_expire" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 30
  }

  assert {
    condition = one([
      for r in aws_s3_bucket_lifecycle_configuration.state.rule : r if r.id == "expire-noncurrent-versions"
    ]).status == "Enabled"
    error_message = "The noncurrent version expiration rule must be enabled."
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.state.rule : r if r.id == "expire-noncurrent-versions"
    ]).noncurrent_version_expiration).noncurrent_days == 30
    error_message = "Noncurrent versions must expire after noncurrent_version_expiration_days."
  }
}

# EN12-AC5: incomplete multipart uploads are aborted
run "en12_ac5_incomplete_multipart_uploads_aborted" {
  command = plan

  variables {
    abort_incomplete_multipart_upload_days = 3
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.state.rule : r if r.id == "abort-incomplete-multipart-uploads"
    ]).abort_incomplete_multipart_upload).days_after_initiation == 3
    error_message = "Incomplete multipart uploads must be aborted after the configured days."
  }
}

# EN12-AC5: rejects noncurrent_version_expiration_days below 1
run "en12_ac5_rejects_noncurrent_days_below_1" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 0
  }

  expect_failures = [var.noncurrent_version_expiration_days]
}

# EN12-AC5: rejects abort_incomplete_multipart_upload_days below 1
run "en12_ac5_rejects_multipart_days_below_1" {
  command = plan

  variables {
    abort_incomplete_multipart_upload_days = 0
  }

  expect_failures = [var.abort_incomplete_multipart_upload_days]
}

# EN12-AC2: rejects a KMS deletion window below 7 days
run "en12_ac2_rejects_deletion_window_below_7" {
  command = plan

  variables {
    kms_deletion_window_in_days = 6
  }

  expect_failures = [var.kms_deletion_window_in_days]
}

# EN12-AC2: rejects a KMS deletion window above 30 days
run "en12_ac2_rejects_deletion_window_above_30" {
  command = plan

  variables {
    kms_deletion_window_in_days = 31
  }

  expect_failures = [var.kms_deletion_window_in_days]
}

# EN12-AC1: rejects an invalid name_prefix
run "en12_ac1_rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Bad_Prefix"
  }

  expect_failures = [var.name_prefix]
}

# EN12-AC1: rejects access logging without a target bucket
run "en12_ac1_rejects_logging_without_target_bucket" {
  command = plan

  variables {
    enable_access_logging = true
  }

  expect_failures = [var.access_log_bucket_name]
}

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
      name   = "us-east-1"
      region = "us-east-1"
    }
  }

  # The mock returns random strings for computed attributes, which aws_s3_bucket_policy.policy and
  # aws_iam_role.assume_role_policy reject as invalid JSON. The invariants are asserted on the document arguments
  # (known at plan), not on the JSON.
  override_data {
    target = data.aws_iam_policy_document.bucket
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.malware_trust
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.malware_permissions
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.tickets_rw
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_resource {
    target = aws_s3_bucket.attachments
    values = {
      id                          = "sc-dev-attachments-123456789012"
      arn                         = "arn:aws:s3:::sc-dev-attachments-123456789012"
      bucket_regional_domain_name = "sc-dev-attachments-123456789012.s3.us-east-1.amazonaws.com"
    }
  }

  override_resource {
    target = aws_iam_role.malware
    values = {
      id  = "sc-dev-attachments-malware-scan"
      arn = "arn:aws:iam::123456789012:role/sc-dev-attachments-malware-scan"
    }
  }
}

variables {
  name_prefix     = "sc-dev"
  kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  allowed_origins = ["https://d111111abcdef8.cloudfront.net"]

  # Required inputs: retention has no default, and malware protection (on by default) needs the boundary.
  object_expiration_days   = 365
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/sc-dev-workload-boundary"
}

# EN-43-AC1: bucket blocks all public access and enforces bucket owner
run "en43_ac1_bucket_private" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.attachments.block_public_acls,
      aws_s3_bucket_public_access_block.attachments.block_public_policy,
      aws_s3_bucket_public_access_block.attachments.ignore_public_acls,
      aws_s3_bucket_public_access_block.attachments.restrict_public_buckets,
    ])
    error_message = "Block Public Access must be fully enabled on the attachments bucket."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.attachments.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "Object ownership must be BucketOwnerEnforced."
  }

  assert {
    condition     = aws_s3_bucket.attachments.bucket == "sc-dev-attachments-123456789012"
    error_message = "Bucket name must be <prefix>-attachments-<account id>."
  }

  assert {
    condition     = aws_s3_bucket.attachments.force_destroy == false
    error_message = "The attachments bucket must not be force-destroyed."
  }
}

# EN-43-AC1: default encryption is SSE-KMS with the data key and bucket key
run "en43_ac1_sse_kms_with_input_key" {
  command = plan

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.attachments.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "Default encryption must be aws:kms."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.attachments.rule).apply_server_side_encryption_by_default).kms_master_key_id == var.kms_key_arn
    error_message = "Default encryption must use the kms_key_arn input."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.attachments.rule).bucket_key_enabled == true
    error_message = "S3 Bucket Keys must be enabled."
  }
}

# EN-43-AC1: versioning is enabled and the lifecycle cleans up multipart uploads and noncurrent versions
run "en43_ac1_versioning_and_lifecycle" {
  command = plan

  variables {
    abort_incomplete_multipart_upload_days = 3
    noncurrent_version_expiration_days     = 14
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.attachments.versioning_configuration).status == "Enabled"
    error_message = "Versioning must be enabled on the attachments bucket."
  }

  assert {
    condition = alltrue([
      for r in aws_s3_bucket_lifecycle_configuration.attachments.rule :
      length(r.abort_incomplete_multipart_upload) == 1 && one(r.abort_incomplete_multipart_upload).days_after_initiation == 3
    ])
    error_message = "Every lifecycle rule must abort incomplete multipart uploads after the configured days (CKV_AWS_300)."
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.attachments.rule : r if r.id == "expire-noncurrent-versions"
    ]).noncurrent_version_expiration).noncurrent_days == 14
    error_message = "Noncurrent versions must expire after noncurrent_version_expiration_days."
  }

  assert {
    condition     = alltrue([for r in aws_s3_bucket_lifecycle_configuration.attachments.rule : r.status == "Enabled"])
    error_message = "Every lifecycle rule must be enabled."
  }
}

# EN-43-AC1: the attachment expiration rule is always present, the quarantine rule is optional
run "en43_ac1_attachment_expiration_always_present" {
  command = plan

  assert {
    condition     = !contains([for r in aws_s3_bucket_lifecycle_configuration.attachments.rule : r.id], "expire-quarantine")
    error_message = "The quarantine expiration rule must not exist unless quarantine_expiration_days is set."
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.attachments.rule : r if r.id == "expire-attachments"
    ]).expiration).days == 365
    error_message = "Attachments must always expire after object_expiration_days."
  }
}

run "en43_ac1_optional_expiration_rules_enabled" {
  command = plan

  variables {
    quarantine_prefix          = "quarantine/"
    quarantine_expiration_days = 2
    object_expiration_days     = 180
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.attachments.rule : r if r.id == "expire-quarantine"
    ]).expiration).days == 2
    error_message = "Objects under the quarantine prefix must expire after quarantine_expiration_days."
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.attachments.rule : r if r.id == "expire-quarantine"
    ]).filter).prefix == "quarantine/"
    error_message = "The quarantine rule must be limited to quarantine_prefix."
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.attachments.rule : r if r.id == "expire-attachments"
    ]).expiration).days == 180
    error_message = "Attachments must expire after object_expiration_days."
  }

  assert {
    condition = alltrue([
      for r in aws_s3_bucket_lifecycle_configuration.attachments.rule : length(r.abort_incomplete_multipart_upload) == 1
    ])
    error_message = "Optional expiration rules must also abort incomplete multipart uploads (CKV_AWS_300)."
  }
}

# EN-43-AC1: bucket policy denies insecure transport, unencrypted puts and other-key puts
run "en43_ac1_bucket_policy_denies_insecure_access" {
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
        c.variable == "s3:x-amz-server-side-encryption-aws-kms-key-id" && c.test == "StringNotEqualsIfExists" && contains(c.values, var.kms_key_arn)
      ])
    ])
    error_message = "The bucket policy must deny puts encrypted with another KMS key."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket.statement :
      s.sid == "DenySSEC" && s.effect == "Deny" && anytrue([
        for c in s.condition :
        c.variable == "s3:x-amz-server-side-encryption-customer-algorithm" && c.test == "Null" && contains(c.values, "false")
      ])
    ])
    error_message = "The bucket policy must deny SSE-C puts."
  }

  assert {
    condition     = alltrue([for s in data.aws_iam_policy_document.bucket.statement : s.effect == "Deny"])
    error_message = "The bucket policy must only contain Deny statements; access is granted by IAM."
  }
}

# EN-43-AC2: CORS is limited to the allowed origins and to GET (download) and POST (upload), never PUT
run "en43_ac2_cors_restricted_to_allowed_origins" {
  command = plan

  variables {
    allowed_origins      = ["https://d111111abcdef8.cloudfront.net", "http://localhost:5173"]
    cors_max_age_seconds = 600
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.attachments.cors_rule).allowed_origins == toset(["https://d111111abcdef8.cloudfront.net", "http://localhost:5173"])
    error_message = "CORS origins must be exactly allowed_origins."
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.attachments.cors_rule).allowed_methods == toset(["GET", "POST"])
    error_message = "CORS methods must be exactly GET and POST."
  }

  assert {
    condition     = !contains(one(aws_s3_bucket_cors_configuration.attachments.cors_rule).allowed_methods, "PUT")
    error_message = "CORS must not allow PUT: uploads go through the presigned POST only."
  }

  assert {
    condition     = !contains(one(aws_s3_bucket_cors_configuration.attachments.cors_rule).allowed_origins, "*")
    error_message = "CORS must not allow every origin."
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.attachments.cors_rule).max_age_seconds == 600
    error_message = "CORS max age must follow cors_max_age_seconds."
  }
}

# EN-43-AC2: the limits of the presigned POST policy (signed by the SE code at runtime) are exposed as contract
run "en43_ac2_post_policy_contract_outputs" {
  command = plan

  assert {
    condition     = output.max_upload_bytes == 10485760
    error_message = "max_upload_bytes must default to 10 MiB (10485760)."
  }

  assert {
    condition     = length(output.allowed_content_types) == 2 && contains(output.allowed_content_types, "image/jpeg") && contains(output.allowed_content_types, "image/png")
    error_message = "allowed_content_types must default to image/jpeg and image/png."
  }

  assert {
    condition     = output.attachments_prefix == "attachments/"
    error_message = "attachments_prefix must default to attachments/."
  }
}

run "en43_ac2_rejects_max_upload_above_10_mib" {
  command = plan

  variables {
    max_upload_bytes = 10485761
  }

  expect_failures = [var.max_upload_bytes]
}

run "en43_ac2_rejects_max_upload_zero" {
  command = plan

  variables {
    max_upload_bytes = 0
  }

  expect_failures = [var.max_upload_bytes]
}

run "en43_ac2_rejects_non_image_content_type" {
  command = plan

  variables {
    allowed_content_types = ["image/jpeg", "application/pdf"]
  }

  expect_failures = [var.allowed_content_types]
}

run "en43_ac2_rejects_empty_content_types" {
  command = plan

  variables {
    allowed_content_types = []
  }

  expect_failures = [var.allowed_content_types]
}

run "en43_ac2_rejects_attachments_prefix_without_slash" {
  command = plan

  variables {
    attachments_prefix = "attachments"
  }

  expect_failures = [var.attachments_prefix]
}

# EN-43-AC5: the "tickets" role policy is limited to the attachments prefix and to Put/GetObject
run "en43_ac5_tickets_policy_scoped_to_prefix" {
  command = plan

  assert {
    condition = length(data.aws_iam_policy_document.tickets_rw.statement) == 1 && alltrue([
      for s in data.aws_iam_policy_document.tickets_rw.statement :
      s.effect == "Allow" &&
      toset(s.actions) == toset(["s3:GetObject", "s3:PutObject"]) &&
      toset(s.resources) == toset(["arn:aws:s3:::sc-dev-attachments-123456789012/attachments/*"]) &&
      length(s.condition) == 0
    ])
    error_message = "The tickets policy must allow only s3:GetObject and s3:PutObject on <bucket>/attachments/*."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.tickets_rw.statement :
      !contains(s.resources, "*") && !contains(s.resources, "arn:aws:s3:::sc-dev-attachments-123456789012") &&
      !contains(s.resources, "arn:aws:s3:::sc-dev-attachments-123456789012/*") &&
      !anytrue([for a in s.actions : a == "*" || endswith(a, ":*")])
    ])
    error_message = "The tickets policy must not reach the whole bucket nor use wildcard actions."
  }
}

run "en43_ac5_tickets_policy_follows_custom_prefix" {
  command = plan

  variables {
    attachments_prefix = "tickets/files/"
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.tickets_rw.statement :
      toset(s.resources) == toset(["arn:aws:s3:::sc-dev-attachments-123456789012/tickets/files/*"])
    ])
    error_message = "The tickets policy must follow attachments_prefix."
  }
}

# EN-43-AC3: malware protection is on by default (fail closed): plan, role and read deny all exist
run "en43_ac3_malware_protection_on_by_default" {
  command = plan

  assert {
    condition     = var.enable_malware_protection == true
    error_message = "enable_malware_protection must default to true."
  }

  assert {
    condition     = length(aws_guardduty_malware_protection_plan.attachments) == 1
    error_message = "The malware protection plan must exist by default."
  }

  assert {
    condition     = length(aws_iam_role.malware) == 1 && length(aws_iam_role_policy.malware) == 1
    error_message = "The malware protection role must exist by default."
  }

  assert {
    condition     = anytrue([for s in data.aws_iam_policy_document.bucket.statement : s.sid == "DenyReadOfUnscannedObjects"])
    error_message = "Unscanned objects must be unreadable by default."
  }
}

# EN-43-AC3: explicit opt-out creates nothing and adds no read deny
run "en43_ac3_malware_protection_explicit_opt_out" {
  command = plan

  variables {
    enable_malware_protection = false
  }

  assert {
    condition     = length(aws_guardduty_malware_protection_plan.attachments) == 0
    error_message = "The malware protection plan must not exist when enable_malware_protection is false."
  }

  assert {
    condition     = length(aws_iam_role.malware) == 0 && length(aws_iam_role_policy.malware) == 0
    error_message = "The malware protection role must not exist when enable_malware_protection is false."
  }

  assert {
    condition     = !anytrue([for s in data.aws_iam_policy_document.bucket.statement : s.sid == "DenyReadOfUnscannedObjects"])
    error_message = "The scan tag read deny must not exist without malware protection: it would block every read."
  }
}

# EN-43-AC3: the plan scans the bucket with tagging enabled, through its service role
run "en43_ac3_malware_protection_plan" {
  command = plan

  variables {
    malware_protection_object_prefixes = ["quarantine/"]
  }

  assert {
    condition     = one(one(aws_guardduty_malware_protection_plan.attachments[0].protected_resource).s3_bucket).bucket_name == "sc-dev-attachments-123456789012"
    error_message = "The plan must protect the attachments bucket."
  }

  assert {
    condition     = one(one(aws_guardduty_malware_protection_plan.attachments[0].protected_resource).s3_bucket).object_prefixes == toset(["quarantine/"])
    error_message = "The plan must scan the configured prefixes."
  }

  assert {
    condition     = one(one(aws_guardduty_malware_protection_plan.attachments[0].actions).tagging).status == "ENABLED"
    error_message = "The plan must tag scanned objects."
  }

  assert {
    condition     = aws_guardduty_malware_protection_plan.attachments[0].role == "arn:aws:iam::123456789012:role/sc-dev-attachments-malware-scan"
    error_message = "The plan must use the dedicated service role."
  }

  assert {
    condition     = output.scan_status_tag_key == "GuardDutyMalwareScanStatus" && output.scan_status_clean_tag_value == "NO_THREATS_FOUND"
    error_message = "The scan tag contract must be exposed."
  }
}

# EN-43-AC3: the service role trusts GuardDuty only, scoped by source account and plan ARN, and carries the boundary
run "en43_ac3_service_role_trust_and_boundary" {
  command = plan

  variables {
    enable_malware_protection = true
    permissions_boundary_arn  = "arn:aws:iam::123456789012:policy/sc-dev-workload-boundary"
  }

  assert {
    condition     = aws_iam_role.malware[0].name == "sc-dev-attachments-malware-scan"
    error_message = "The role name must be <prefix>-attachments-malware-scan."
  }

  assert {
    condition     = aws_iam_role.malware[0].permissions_boundary == "arn:aws:iam::123456789012:policy/sc-dev-workload-boundary"
    error_message = "The service role must carry the permissions boundary."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.malware_trust[0].statement :
      s.effect == "Allow" && toset(s.actions) == toset(["sts:AssumeRole"]) &&
      alltrue([for p in s.principals : p.type == "Service" && p.identifiers == toset(["malware-protection-plan.guardduty.amazonaws.com"])])
    ])
    error_message = "The role must be assumable by the GuardDuty malware protection service principal only."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.malware_trust[0].statement :
      anytrue([for c in s.condition : c.variable == "aws:SourceAccount" && c.test == "StringEquals" && toset(c.values) == toset(["123456789012"])])
    ])
    error_message = "The trust policy must pin aws:SourceAccount."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.malware_trust[0].statement :
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceArn" && c.test == "ArnLike" && toset(c.values) == toset(["arn:aws:guardduty:us-east-1:123456789012:malware-protection-plan/*"])
      ])
    ])
    error_message = "The trust policy must pin aws:SourceArn to the malware protection plans of the account and region."
  }
}

# EN-43-AC3: the role policy is scoped to the bucket, its key and the GuardDuty rules
run "en43_ac3_service_role_policy_least_privilege" {
  command = plan

  variables {
    enable_malware_protection = true
    permissions_boundary_arn  = "arn:aws:iam::123456789012:policy/sc-dev-workload-boundary"
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.malware_permissions[0].statement :
      s.effect == "Allow" && !anytrue([for a in s.actions : a == "*" || endswith(a, ":*")])
    ])
    error_message = "The role policy must list explicit actions."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.malware_permissions[0].statement :
      !contains(s.resources, "*")
    ])
    error_message = "The role policy must not use Resource \"*\"."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.malware_permissions[0].statement :
      s.sid == "ScanAndTagObjects" && toset(s.resources) == toset(["arn:aws:s3:::sc-dev-attachments-123456789012/*"]) &&
      contains(s.actions, "s3:GetObject") && contains(s.actions, "s3:PutObjectTagging")
    ])
    error_message = "The scanner must read and tag objects of the attachments bucket only."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.malware_permissions[0].statement :
      s.sid == "UseDataKeyThroughS3" && toset(s.resources) == toset([var.kms_key_arn]) &&
      toset(s.actions) == toset(["kms:Decrypt", "kms:GenerateDataKey"]) &&
      anytrue([for c in s.condition : c.variable == "kms:ViaService" && contains(c.values, "s3.us-east-1.amazonaws.com")])
    ])
    error_message = "The scanner must use the data key only through S3."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.malware_permissions[0].statement :
      s.sid == "ManageGuardDutyEventRules" &&
      toset(s.resources) == toset(["arn:aws:events:us-east-1:123456789012:rule/DO-NOT-DELETE-AmazonGuardDutyMalwareProtectionS3*"]) &&
      anytrue([for c in s.condition : c.variable == "events:ManagedBy" && contains(c.values, "malware-protection-plan.guardduty.amazonaws.com")])
    ])
    error_message = "EventBridge rule management must be limited to the GuardDuty managed rules."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.malware_permissions[0].statement :
      s.sid == "ManageGuardDutyEventRules" &&
      !contains(s.actions, "events:DescribeRule") && !contains(s.actions, "events:ListTargetsByRule")
    ])
    error_message = "The read-only EventBridge calls must not sit in the ManagedBy-conditioned statement."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.malware_permissions[0].statement :
      s.sid == "AllowGuardDutyToMonitorEventBridgeManagedRule" && s.effect == "Allow" &&
      toset(s.actions) == toset(["events:DescribeRule", "events:ListTargetsByRule"]) &&
      toset(s.resources) == toset(["arn:aws:events:us-east-1:123456789012:rule/DO-NOT-DELETE-AmazonGuardDutyMalwareProtectionS3*"]) &&
      length(s.condition) == 0
    ])
    error_message = "DescribeRule and ListTargetsByRule must be granted without condition on the GuardDuty managed rules only."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.malware_permissions[0].statement :
      s.sid == "AllowPutValidationObject" && s.effect == "Allow" &&
      toset(s.actions) == toset(["s3:PutObject"]) &&
      toset(s.resources) == toset(["arn:aws:s3:::sc-dev-attachments-123456789012/malware-protection-resource-validation-object"])
    ])
    error_message = "The role must be able to put the validation object, and only that key."
  }
}

# EN-43-AC4: objects not tagged clean cannot be read, except by the scanner
run "en43_ac4_read_denied_unless_tagged_clean" {
  command = plan

  variables {
    enable_malware_protection = true
    permissions_boundary_arn  = "arn:aws:iam::123456789012:policy/sc-dev-workload-boundary"
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket.statement :
      s.sid == "DenyReadOfUnscannedObjects" && s.effect == "Deny" &&
      contains(s.actions, "s3:GetObject") && contains(s.actions, "s3:GetObjectVersion") &&
      toset(s.resources) == toset(["arn:aws:s3:::sc-dev-attachments-123456789012/*"]) &&
      anytrue([
        for c in s.condition :
        c.test == "StringNotEquals" && c.variable == "s3:ExistingObjectTag/GuardDutyMalwareScanStatus" && toset(c.values) == toset(["NO_THREATS_FOUND"])
      ]) &&
      anytrue([
        for c in s.condition :
        c.test == "ArnNotEquals" && c.variable == "aws:PrincipalArn" && toset(c.values) == toset(["arn:aws:iam::123456789012:role/sc-dev-attachments-malware-scan"])
      ])
    ])
    error_message = "GetObject must be denied on objects not tagged GuardDutyMalwareScanStatus=NO_THREATS_FOUND, except for the scanner role."
  }
}

# EN-43-AC4: nobody but the scanner can write or remove the scan tag
run "en43_ac4_scan_tag_cannot_be_forged" {
  command = plan

  variables {
    enable_malware_protection = true
    permissions_boundary_arn  = "arn:aws:iam::123456789012:policy/sc-dev-workload-boundary"
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket.statement :
      s.sid == "DenyForgedScanTagOnPut" && s.effect == "Deny" &&
      contains(s.actions, "s3:PutObject") && contains(s.actions, "s3:PutObjectTagging") &&
      anytrue([
        for c in s.condition :
        c.test == "ForAnyValue:StringEquals" && c.variable == "s3:RequestObjectTagKeys" && contains(c.values, "GuardDutyMalwareScanStatus")
      ]) &&
      anytrue([
        for c in s.condition :
        c.test == "ArnNotEquals" && c.variable == "aws:PrincipalArn" && contains(c.values, "arn:aws:iam::123456789012:role/sc-dev-attachments-malware-scan")
      ])
    ])
    error_message = "Writing the scan tag must be denied to every principal but the scanner role."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket.statement :
      s.sid == "DenyScanTagRemoval" && s.effect == "Deny" && contains(s.actions, "s3:DeleteObjectTagging")
    ])
    error_message = "Removing the scan tag must be denied to every principal but the scanner role."
  }
}

# EN-43-AC1: rejects an empty origin list
run "en43_ac1_rejects_empty_allowed_origins" {
  command = plan

  variables {
    allowed_origins = []
  }

  expect_failures = [var.allowed_origins]
}

# EN-43-AC1: rejects wildcard origins
run "en43_ac1_rejects_wildcard_origin" {
  command = plan

  variables {
    allowed_origins = ["*"]
  }

  expect_failures = [var.allowed_origins]
}

# EN-43-AC1: rejects plain http origins other than localhost
run "en43_ac1_rejects_insecure_origin" {
  command = plan

  variables {
    allowed_origins = ["http://campus.example.com"]
  }

  expect_failures = [var.allowed_origins]
}

# EN-43-AC1: rejects a KMS alias in place of a key ARN
run "en43_ac1_rejects_kms_alias" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:alias/sc-dev-data"
  }

  expect_failures = [var.kms_key_arn]
}

# EN-43-AC1: rejects an invalid name_prefix
run "en43_ac1_rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Bad_Prefix"
  }

  expect_failures = [var.name_prefix]
}

# EN-43-AC1: rejects lifecycle durations below 1 day
run "en43_ac1_rejects_noncurrent_days_below_1" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 0
  }

  expect_failures = [var.noncurrent_version_expiration_days]
}

run "en43_ac1_rejects_multipart_days_below_1" {
  command = plan

  variables {
    abort_incomplete_multipart_upload_days = 0
  }

  expect_failures = [var.abort_incomplete_multipart_upload_days]
}

run "en43_ac1_rejects_quarantine_days_below_1" {
  command = plan

  variables {
    quarantine_expiration_days = 0
  }

  expect_failures = [var.quarantine_expiration_days]
}

run "en43_ac1_rejects_object_expiration_days_below_1" {
  command = plan

  variables {
    object_expiration_days = 0
  }

  expect_failures = [var.object_expiration_days]
}

run "en43_ac1_rejects_quarantine_prefix_without_slash" {
  command = plan

  variables {
    quarantine_prefix = "quarantine"
  }

  expect_failures = [var.quarantine_prefix]
}

# EN-43-AC3: the boundary is required with malware protection
run "en43_ac3_rejects_malware_protection_without_boundary" {
  command = plan

  variables {
    enable_malware_protection = true
    permissions_boundary_arn  = null
  }

  expect_failures = [var.permissions_boundary_arn]
}

# EN-43-AC1: the retention is required: zero is refused
run "en43_ac1_rejects_zero_object_expiration_days" {
  command = plan

  variables {
    object_expiration_days = 0
  }

  expect_failures = [var.object_expiration_days]
}

run "en43_ac1_rejects_fractional_object_expiration_days" {
  command = plan

  variables {
    object_expiration_days = 1.5
  }

  expect_failures = [var.object_expiration_days]
}

# EN-43-AC3: rejects a boundary that is not an IAM policy ARN
run "en43_ac3_rejects_invalid_boundary_arn" {
  command = plan

  variables {
    enable_malware_protection = true
    permissions_boundary_arn  = "sc-dev-workload-boundary"
  }

  expect_failures = [var.permissions_boundary_arn]
}

# EN-43-AC3: rejects more than 5 scanned prefixes
run "en43_ac3_rejects_too_many_scan_prefixes" {
  command = plan

  variables {
    malware_protection_object_prefixes = ["a/", "b/", "c/", "d/", "e/", "f/"]
  }

  expect_failures = [var.malware_protection_object_prefixes]
}

mock_provider "aws" {
  # Fake documentation account ID, used only to keep names and ARNs predictable.
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

  # The provider ARN is computed: without an override the trust and boundary documents depend on an unknown value and
  # their arguments cannot be asserted at plan time.
  override_resource {
    target = aws_iam_openid_connect_provider.github
    values = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  # Managed policy ARNs are computed; the mock's random strings are rejected by the attachment resources.
  override_resource {
    target = aws_iam_policy.ci_boundary
    values = {
      arn = "arn:aws:iam::123456789012:policy/sc-ci-boundary"
    }
  }

  override_resource {
    target = aws_iam_policy.workload_boundary
    values = {
      arn = "arn:aws:iam::123456789012:policy/sc-workload-boundary"
    }
  }

  override_resource {
    target = aws_iam_policy.apply
    values = {
      arn = "arn:aws:iam::123456789012:policy/sc-gha-apply"
    }
  }

  # The mock returns random strings for computed attributes, which the role and policy resources reject as invalid
  # JSON. The invariants are asserted on the document arguments (known at plan), not on the JSON.
  override_data {
    target = data.aws_iam_policy_document.trust_plan
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.trust_apply
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.plan_state
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.plan_deny
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.apply_state
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.apply_iam
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.apply_compute
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.apply_data
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.apply_edge
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.apply_cdn
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.apply_guardrails
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.ci_boundary
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.workload_boundary
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix       = "sc"
  github_repository = "smart-campus-ai/smart-campus-ai"
  allowed_regions   = ["eu-west-3", "us-east-1"]
  state_bucket_arn  = "arn:aws:s3:::sc-tfstate-123456789012"
  state_kms_key_arn = "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000"
}

# =====================================================================================================================
# EN-13-AC1: plan role, read-only, assumed by pull_request workflows only
# =====================================================================================================================

# EN-13-AC1: the OIDC provider accepts the STS audience only
run "en13_ac1_oidc_provider_created_for_sts_audience" {
  command = plan

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1
    error_message = "The GitHub OIDC provider must be created by default."
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github[0].url == "https://token.actions.githubusercontent.com"
    error_message = "The provider URL must be the GitHub Actions token issuer."
  }

  assert {
    condition     = toset(aws_iam_openid_connect_provider.github[0].client_id_list) == toset(["sts.amazonaws.com"])
    error_message = "The provider must accept the sts.amazonaws.com audience only."
  }
}

# EN-13-AC1: an existing provider is reused instead of creating a second one
run "en13_ac1_existing_oidc_provider_is_reused" {
  command = plan

  variables {
    create_oidc_provider       = false
    existing_oidc_provider_arn = "arn:aws:iam::210987654321:oidc-provider/token.actions.githubusercontent.com"
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "No provider may be created when create_oidc_provider is false."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.trust_plan.statement :
      alltrue([for p in s.principals : toset(p.identifiers) == toset(["arn:aws:iam::210987654321:oidc-provider/token.actions.githubusercontent.com"])])
    ])
    error_message = "The plan trust policy must use the existing provider ARN."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      alltrue([
        for s in data.aws_iam_policy_document.trust_apply[e].statement :
        alltrue([for p in s.principals : toset(p.identifiers) == toset(["arn:aws:iam::210987654321:oidc-provider/token.actions.githubusercontent.com"])])
      ])
    ])
    error_message = "The apply trust policies must use the existing provider ARN."
  }
}

# EN-13-AC1: trust is pinned to the repository pull_request subject and the STS audience
run "en13_ac1_plan_trust_pinned_to_pull_request" {
  command = plan

  assert {
    condition     = length(data.aws_iam_policy_document.trust_plan.statement) == 1
    error_message = "The plan trust policy must contain exactly one statement."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.trust_plan.statement :
      s.effect == "Allow" && toset(s.actions) == toset(["sts:AssumeRoleWithWebIdentity"]) &&
      length(s.principals) == 1 &&
      alltrue([
        for p in s.principals :
        p.type == "Federated" && toset(p.identifiers) == toset(["arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"])
      ])
    ])
    error_message = "The plan role must be assumable through sts:AssumeRoleWithWebIdentity by the GitHub OIDC provider only."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.trust_plan.statement :
      anytrue([
        for c in s.condition :
        c.test == "StringEquals" && c.variable == "token.actions.githubusercontent.com:sub" &&
        toset(c.values) == toset(["repo:smart-campus-ai/smart-campus-ai:pull_request"])
      ])
    ])
    error_message = "The plan trust sub must be exactly repo:smart-campus-ai/smart-campus-ai:pull_request."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.trust_plan.statement :
      anytrue([
        for c in s.condition :
        c.test == "StringEquals" && c.variable == "token.actions.githubusercontent.com:aud" &&
        toset(c.values) == toset(["sts.amazonaws.com"])
      ])
    ])
    error_message = "The plan trust aud must be exactly sts.amazonaws.com."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.trust_plan.statement :
      length(s.condition) == 2 && alltrue([for c in s.condition : c.test == "StringEquals"])
    ])
    error_message = "The plan trust must carry exactly the aud and sub conditions, both StringEquals (never StringLike)."
  }
}

# EN-13-AC1: role identity, boundary and session length
run "en13_ac1_plan_role_boundary_and_session" {
  command = plan

  assert {
    condition     = aws_iam_role.plan.name == "sc-gha-plan"
    error_message = "The plan role must be named <prefix>-gha-plan."
  }

  assert {
    condition     = aws_iam_role.plan.permissions_boundary == "arn:aws:iam::123456789012:policy/sc-ci-boundary"
    error_message = "The plan role must carry the ci boundary."
  }

  assert {
    condition     = aws_iam_role.plan.max_session_duration == 3600
    error_message = "The plan role session must not exceed 3600 seconds."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.plan_read_only.policy_arn == "arn:aws:iam::aws:policy/ReadOnlyAccess"
    error_message = "The plan role must get the AWS managed ReadOnlyAccess policy."
  }
}

# EN-13-AC1 (F6): the plan role has no S3 write at all (PR plans run with -lock=false, so no lock file is written)
run "en13_ac1_plan_role_has_no_s3_write" {
  command = plan

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.plan_state.statement :
      s.effect == "Allow"
    ])
    error_message = "The plan state policy must only contain Allow statements; the Denies live in plan_deny."
  }

  assert {
    condition = !anytrue([
      for s in data.aws_iam_policy_document.plan_state.statement :
      anytrue([for a in s.actions : startswith(a, "s3:") && !contains(["s3:GetObject", "s3:ListBucket"], a)])
    ])
    error_message = "The plan role may only use s3:GetObject and s3:ListBucket: no PutObject, DeleteObject or lock-file write."
  }

  assert {
    condition = !anytrue([
      for s in data.aws_iam_policy_document.plan_state.statement :
      anytrue([for r in s.resources : strcontains(r, ".tflock")])
    ])
    error_message = "The plan role must not name lock files."
  }

  assert {
    condition = length(setsubtract(
      toset(flatten([for s in data.aws_iam_policy_document.plan_state.statement : tolist(s.actions)])),
      toset(["s3:GetObject", "s3:ListBucket", "kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"])
    )) == 0
    error_message = "The plan state policy may only use the listed read and state key usage actions."
  }
}

# EN-13-AC1 (F5): the plan role reads the dev state only, never prod or bootstrap/
run "en13_ac1_plan_role_reads_dev_state_only" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.plan_state.statement :
      s.sid == "StateRead" && toset(s.actions) == toset(["s3:GetObject"]) && toset(s.resources) == toset(["arn:aws:s3:::sc-tfstate-123456789012/dev/*"])
    ])
    error_message = "The plan role must read the state objects under dev/* only."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.plan_state.statement :
      alltrue([for r in s.resources : !strcontains(r, "/prod/") && !strcontains(r, "/bootstrap/") && r != "arn:aws:s3:::sc-tfstate-123456789012/*"])
    ])
    error_message = "No plan statement may reach prod/, bootstrap/ or the whole bucket."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.plan_state.statement :
      s.sid == "StateList" && toset(s.actions) == toset(["s3:ListBucket"]) && toset(s.resources) == toset([var.state_bucket_arn]) &&
      anytrue([
        for c in s.condition :
        c.test == "StringLikeIfExists" && c.variable == "s3:prefix" && toset(c.values) == toset(["dev", "dev/*"])
      ])
    ])
    error_message = "Listing the state bucket must be conditioned on the dev s3:prefix."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.plan_state.statement :
      s.sid == "StateKeyUsage" && toset(s.resources) == toset([var.state_kms_key_arn]) &&
      !anytrue([for a in s.actions : contains(["kms:ScheduleKeyDeletion", "kms:PutKeyPolicy", "kms:DisableKey", "kms:CreateGrant"], a)])
    ])
    error_message = "The plan role must get usage of the state key only, without administration actions."
  }
}

# EN-13-AC1: data-plane reads of secrets and personal data stay denied whatever ReadOnlyAccess grants
run "en13_ac1_plan_role_denies_data_plane_reads" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.plan_deny.statement :
      s.sid == "DenyDataPlaneReads" && s.effect == "Deny" &&
      length(setsubtract(
        toset(["secretsmanager:GetSecretValue", "dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan", "dynamodb:BatchGetItem", "logs:GetLogEvents", "logs:FilterLogEvents", "sqs:ReceiveMessage", "cognito-idp:ListUsers", "cognito-idp:AdminGetUser"]),
        s.actions
      )) == 0
    ])
    error_message = "plan_deny must deny secret, table, log, queue and user-pool data reads."
  }

  # F7: stream and query-result reads are data-plane too (ticket contents leave through DynamoDB streams)
  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.plan_deny.statement :
      s.sid == "DenyDataPlaneReads" && s.effect == "Deny" &&
      length(setsubtract(
        toset(["dynamodb:GetRecords", "dynamodb:GetShardIterator", "kinesis:GetRecords", "athena:GetQueryResults"]),
        s.actions
      )) == 0
    ])
    error_message = "plan_deny must deny dynamodb:GetRecords, dynamodb:GetShardIterator, kinesis:GetRecords and athena:GetQueryResults."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.plan_deny.statement :
      s.sid == "DenyDecryptExceptStateKey" && s.effect == "Deny" && toset(s.actions) == toset(["kms:Decrypt"]) &&
      toset(s.not_resources) == toset([var.state_kms_key_arn])
    ])
    error_message = "kms:Decrypt must be denied on every key except the state key (this protects SecureString parameters)."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.plan_deny.statement :
      s.sid == "DenyObjectReadsExceptState" && s.effect == "Deny" && contains(s.actions, "s3:GetObject") &&
      toset(s.not_resources) == toset(["arn:aws:s3:::sc-tfstate-123456789012/dev/*"])
    ])
    error_message = "s3:GetObject must be denied on every object except the dev state objects."
  }
}

# =====================================================================================================================
# EN-13-AC2: apply roles per environment
# =====================================================================================================================

# EN-13-AC2: trust is pinned to the GitHub environment of each role
run "en13_ac2_apply_trust_pinned_to_environment" {
  command = plan

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.trust_apply[e].statement :
        anytrue([
          for c in s.condition :
          c.test == "StringEquals" && c.variable == "token.actions.githubusercontent.com:sub" &&
          toset(c.values) == toset(["repo:smart-campus-ai/smart-campus-ai:environment:${e}"])
        ])
      ])
    ])
    error_message = "Each apply trust sub must be exactly repo:smart-campus-ai/smart-campus-ai:environment:<env>."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      alltrue([
        for s in data.aws_iam_policy_document.trust_apply[e].statement :
        s.effect == "Allow" && toset(s.actions) == toset(["sts:AssumeRoleWithWebIdentity"]) &&
        length(s.condition) == 2 && alltrue([for c in s.condition : c.test == "StringEquals"]) &&
        anytrue([
          for c in s.condition :
          c.variable == "token.actions.githubusercontent.com:aud" && toset(c.values) == toset(["sts.amazonaws.com"])
        ])
      ])
    ])
    error_message = "Each apply trust must carry StringEquals conditions on aud (sts.amazonaws.com) and sub only."
  }
}

# EN-13-AC2: no wildcard in any trust condition, and the plan subject never opens an apply role
run "en13_ac2_trust_policies_have_no_wildcard" {
  command = plan

  assert {
    condition = alltrue(flatten([
      [
        for s in data.aws_iam_policy_document.trust_plan.statement :
        [for c in s.condition : alltrue([for v in c.values : !strcontains(v, "*") && !strcontains(v, "?")])]
      ],
      [
        for e in ["dev", "prod"] : [
          for s in data.aws_iam_policy_document.trust_apply[e].statement :
          [for c in s.condition : alltrue([for v in c.values : !strcontains(v, "*") && !strcontains(v, "?") && !endswith(v, ":pull_request")])]
        ]
      ],
    ]))
    error_message = "Trust conditions must not contain wildcards, and apply roles must not trust the pull_request subject."
  }
}

# EN-13-AC2: role identity, boundary, session length
run "en13_ac2_apply_roles_boundary_and_session" {
  command = plan

  assert {
    condition     = toset(keys(aws_iam_role.apply)) == toset(["dev", "prod"])
    error_message = "There must be exactly one apply role per environment."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      aws_iam_role.apply[e].name == "sc-gha-apply-${e}"
    ])
    error_message = "Apply roles must be named <prefix>-gha-apply-<env>."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      aws_iam_role.apply[e].permissions_boundary == "arn:aws:iam::123456789012:policy/sc-ci-boundary"
    ])
    error_message = "Apply roles must carry the ci boundary."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      aws_iam_role.apply[e].max_session_duration == 3600
    ])
    error_message = "Apply role sessions must not exceed 3600 seconds."
  }
}

# EN-13-AC2: every apply policy is attached to the role of its own environment
run "en13_ac2_apply_policies_attached_to_own_environment" {
  command = plan

  assert {
    condition     = length(aws_iam_policy.apply) == 14 && length(aws_iam_role_policy_attachment.apply) == 14
    error_message = "Each environment must get seven apply policies, all attached."
  }

  assert {
    condition = alltrue([
      for k, a in aws_iam_role_policy_attachment.apply :
      a.role == (startswith(k, "dev-") ? "sc-gha-apply-dev" : "sc-gha-apply-prod")
    ])
    error_message = "An apply policy must be attached to the apply role of its own environment only."
  }

  assert {
    condition = alltrue([
      for k, p in aws_iam_policy.apply :
      startswith(p.name, startswith(k, "dev-") ? "sc-gha-apply-dev-" : "sc-gha-apply-prod-")
    ])
    error_message = "Apply policy names must start with the name of their role."
  }
}

# EN-13-AC2: state access is limited to the prefix of the environment
run "en13_ac2_apply_state_access_limited_to_env_prefix" {
  command = plan

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_state[e].statement :
        s.sid == "StateObjects" && s.effect == "Allow" &&
        toset(s.actions) == toset(["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]) &&
        toset(s.resources) == toset(["arn:aws:s3:::sc-tfstate-123456789012/${e}/*"])
      ])
    ])
    error_message = "State objects must be reachable under <env>/* only."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_state[e].statement :
        s.sid == "StateList" && s.effect == "Allow" && toset(s.actions) == toset(["s3:ListBucket"]) &&
        toset(s.resources) == toset([var.state_bucket_arn]) &&
        anytrue([
          for c in s.condition :
          c.variable == "s3:prefix" && toset(c.values) == toset([e, "${e}/*"])
        ])
      ])
    ])
    error_message = "Listing the state bucket must be conditioned on the s3:prefix of the environment."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_state[e].statement :
        s.sid == "StateKeyUsage" && toset(s.resources) == toset([var.state_kms_key_arn]) &&
        toset(s.actions) == toset(["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"])
      ])
    ])
    error_message = "The apply roles must get usage of the state key only."
  }
}

# EN-13-AC2: the other environment, bootstrap and the state bucket settings are explicitly protected
run "en13_ac2_apply_guardrails_protect_state" {
  command = plan

  assert {
    condition = alltrue([
      for e, o in { dev = "prod", prod = "dev" } :
      anytrue([
        for s in data.aws_iam_policy_document.apply_guardrails[e].statement :
        s.sid == "DenyOtherEnvAndBootstrapStateWrite" && s.effect == "Deny" &&
        toset(s.resources) == toset(["arn:aws:s3:::sc-tfstate-123456789012/${o}/*", "arn:aws:s3:::sc-tfstate-123456789012/bootstrap/*"]) &&
        contains(s.actions, "s3:PutObject") && contains(s.actions, "s3:DeleteObject")
      ])
    ])
    error_message = "Each apply role must be denied writes on the other environment and on bootstrap/."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_guardrails[e].statement :
        s.sid == "DenyStateKeyDestruction" && s.effect == "Deny" && toset(s.resources) == toset([var.state_kms_key_arn]) &&
        toset(s.actions) == toset(["kms:CreateGrant", "kms:DisableKey", "kms:DisableKeyRotation", "kms:PutKeyPolicy", "kms:ScheduleKeyDeletion", "kms:TagResource", "kms:UntagResource"])
      ])
    ])
    error_message = "ScheduleKeyDeletion, PutKeyPolicy, DisableKey, CreateGrant and (un)tagging must be denied on the state key."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_guardrails[e].statement :
        s.sid == "DenyStateBucketTampering" && s.effect == "Deny" && toset(s.resources) == toset([var.state_bucket_arn]) &&
        length(setsubtract(toset(["s3:PutBucketPolicy", "s3:PutBucketVersioning", "s3:PutLifecycleConfiguration", "s3:DeleteBucket*", "s3:PutBucketPublicAccessBlock"]), s.actions)) == 0
      ])
    ])
    error_message = "Bucket policy, versioning, lifecycle, public access block and deletion must be denied on the state bucket."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_guardrails[e].statement :
        s.sid == "DenyStateVersionDeletion" && s.effect == "Deny" && toset(s.actions) == toset(["s3:DeleteObjectVersion"]) &&
        toset(s.resources) == toset(["arn:aws:s3:::sc-tfstate-123456789012/*"])
      ])
    ])
    error_message = "State object versions must not be deletable."
  }
}

# EN-13-AC2: named resources are scoped by the environment prefix
run "en13_ac2_apply_resources_scoped_by_env_prefix" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for e in ["dev", "prod"] : [
        for s in data.aws_iam_policy_document.apply_compute[e].statement :
        alltrue([for r in s.resources : strcontains(r, "sc-${e}-")])
        if !contains(["NoResourceLevel", "LambdaEventSourceMappingsWrite", "LambdaEventSourceMappingsManage"], s.sid)
      ]
    ]))
    error_message = "Every compute, messaging and observability resource must be scoped by sc-<env>-."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_compute[e].statement :
        s.sid == "LambdaEventSourceMappingsWrite" &&
        anytrue([
          for c in s.condition :
          c.test == "ArnLike" && c.variable == "lambda:FunctionArn" && alltrue([for v in c.values : strcontains(v, "function:sc-${e}-")])
        ])
      ])
    ])
    error_message = "Event source mapping writes must be tied to a function of the environment."
  }

  assert {
    condition = alltrue(flatten([
      for e in ["dev", "prod"] : [
        for s in data.aws_iam_policy_document.apply_data[e].statement :
        alltrue([for r in s.resources : strcontains(r, "sc-${e}-")])
        if contains(["Buckets", "KeyAliases"], s.sid)
      ]
    ]))
    error_message = "Buckets and key aliases must be scoped by sc-<env>-."
  }

  assert {
    condition = alltrue(flatten([
      for e in ["dev", "prod"] : [
        for s in data.aws_iam_policy_document.apply_data[e].statement :
        alltrue([for r in s.resources : strcontains(r, "/smartcampus/${e}/")])
        if s.sid == "Parameters"
      ]
    ]))
    error_message = "SSM parameters must be scoped by /smartcampus/<env>/."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_data[e].statement :
        s.sid == "KeyManage" && s.effect == "Allow" &&
        anytrue([
          for c in s.condition :
          c.test == "StringEquals" && c.variable == "aws:ResourceTag/Environment" && toset(c.values) == toset([e])
        ])
      ]) &&
      anytrue([
        for s in data.aws_iam_policy_document.apply_data[e].statement :
        s.sid == "KeyCreate" && s.effect == "Allow" &&
        anytrue([
          for c in s.condition :
          c.test == "StringEquals" && c.variable == "aws:RequestTag/Environment" && toset(c.values) == toset([e])
        ])
      ])
    ])
    error_message = "KMS keys must be created and managed only with the Environment tag of the role."
  }
}

# EN-13-AC2 (F2): a key can be created, but not retagged across environments, nor have its Environment tag rewritten
run "en13_ac2_kms_key_creation_cannot_retag_across_environments" {
  command = plan

  # KeyCreate is CreateKey only; TagResource (required by KMS to create a key with tags) is a separate statement
  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_data[e].statement :
        s.sid == "KeyCreate" && s.effect == "Allow" && toset(s.actions) == toset(["kms:CreateKey"]) && toset(s.resources) == toset(["*"]) &&
        anytrue([for c in s.condition : c.test == "StringEquals" && c.variable == "aws:RequestTag/Environment" && toset(c.values) == toset([e])])
      ])
    ])
    error_message = "KeyCreate must be kms:CreateKey only, conditioned on the Environment request tag."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_data[e].statement :
        s.sid == "KeyTagOnCreate" && s.effect == "Allow" && toset(s.actions) == toset(["kms:TagResource"]) && !contains(s.resources, "*") &&
        anytrue([for c in s.condition : c.test == "StringEquals" && c.variable == "aws:RequestTag/Environment" && toset(c.values) == toset([e])])
      ])
    ])
    error_message = "kms:TagResource for key creation must not be on Resource \"*\" and must require the Environment request tag."
  }

  # Deny retagging a key (or CloudFront / Cognito resource) whose Environment tag is another environment
  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_guardrails[e].statement :
        s.sid == "DenyForeignEnvironmentTagging" && s.effect == "Deny" &&
        length(setsubtract(toset(["kms:TagResource", "kms:UntagResource"]), s.actions)) == 0 &&
        anytrue([for c in s.condition : c.test == "Null" && c.variable == "aws:ResourceTag/Environment" && toset(c.values) == toset(["false"])]) &&
        anytrue([for c in s.condition : c.test == "StringNotEquals" && c.variable == "aws:ResourceTag/Environment" && toset(c.values) == toset([e])])
      ])
    ])
    error_message = "kms:TagResource / UntagResource must be denied when aws:ResourceTag/Environment exists and is not the environment of the role."
  }

  # Deny rewriting the Environment tag key of a resource that already has it
  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_guardrails[e].statement :
        s.sid == "DenyEnvironmentTagChange" && s.effect == "Deny" &&
        length(setsubtract(toset(["kms:TagResource", "kms:UntagResource"]), s.actions)) == 0 &&
        anytrue([for c in s.condition : c.test == "Null" && c.variable == "aws:ResourceTag/Environment" && toset(c.values) == toset(["false"])]) &&
        anytrue([for c in s.condition : c.test == "ForAnyValue:StringEqualsIgnoreCase" && c.variable == "aws:TagKeys" && toset(c.values) == toset(["Environment"])])
      ])
    ])
    error_message = "Changing the Environment tag key of a tagged key must be denied."
  }

  # The state key (Environment=shared) cannot be granted to, retagged or untagged either
  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_guardrails[e].statement :
        s.sid == "DenyStateKeyDestruction" && s.effect == "Deny" &&
        length(setsubtract(toset(["kms:CreateGrant", "kms:TagResource", "kms:UntagResource"]), s.actions)) == 0
      ])
    ])
    error_message = "kms:CreateGrant, kms:TagResource and kms:UntagResource must be denied on the state key."
  }
}

# EN-13-AC2 (F4): API Gateway, Cognito, WAF and CloudFront distributions are limited to the Environment tag
run "en13_ac2_id_addressed_services_limited_by_environment_tag" {
  command = plan

  # Every Allow of apigateway / cognito-idp / wafv2 / cloudfront on a distribution carries a tag condition,
  # except the closed list below (name-scoped, singleton or non-taggable resources)
  assert {
    condition = alltrue(flatten([
      for e in ["dev", "prod"] : [
        for s in concat(tolist(data.aws_iam_policy_document.apply_edge[e].statement), tolist(data.aws_iam_policy_document.apply_cdn[e].statement)) :
        anytrue([
          for c in s.condition :
          c.test == "StringEquals" && contains(["aws:ResourceTag/Environment", "aws:RequestTag/Environment"], c.variable) && toset(c.values) == toset([e])
        ])
        if s.effect == "Allow" && !contains(["ApiGatewayAccount", "ApiGatewayTags", "Wafv2ManagedRuleGroups", "CloudFrontFunctions", "CloudFrontSupportingRead", "CloudFrontSupportingWrite", "Ses", "BedrockModelsRead", "Acm"], s.sid)
      ]
    ]))
    error_message = "Every API Gateway, Cognito, WAF and CloudFront distribution statement must be conditioned on the Environment tag of the role."
  }

  # Creation = request tag, management = resource tag
  assert {
    condition = alltrue(flatten([
      for e in ["dev", "prod"] : [
        for s in concat(tolist(data.aws_iam_policy_document.apply_edge[e].statement), tolist(data.aws_iam_policy_document.apply_cdn[e].statement)) :
        (endswith(s.sid, "Create") || endswith(s.sid, "TagOnCreate")) ?
        anytrue([for c in s.condition : c.variable == "aws:RequestTag/Environment"]) :
        anytrue([for c in s.condition : c.variable == "aws:ResourceTag/Environment"])
        if contains(["ApiGatewayCreate", "ApiGatewayManage", "CognitoCreate", "CognitoTagOnCreate", "CognitoManage", "BedrockCreate", "BedrockTagOnCreate", "BedrockManage", "Wafv2Create", "Wafv2Manage", "CloudFrontDistributionCreate", "CloudFrontDistributionManage"], s.sid)
      ]
    ]))
    error_message = "Create statements must use aws:RequestTag/Environment, manage statements aws:ResourceTag/Environment."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      length(setsubtract(
        toset(["ApiGatewayCreate", "ApiGatewayManage", "CognitoCreate", "CognitoTagOnCreate", "CognitoManage", "BedrockCreate", "BedrockTagOnCreate", "BedrockManage", "Wafv2Create", "Wafv2Manage", "CloudFrontDistributionCreate", "CloudFrontDistributionManage"]),
        toset([for s in concat(tolist(data.aws_iam_policy_document.apply_edge[e].statement), tolist(data.aws_iam_policy_document.apply_cdn[e].statement)) : s.sid])
      )) == 0
    ])
    error_message = "The tag-conditioned create and manage statements must exist for API Gateway, Cognito, WAF and CloudFront."
  }

  # No statement left with an unconditioned service wildcard on a generated-ID resource
  assert {
    condition = alltrue(flatten([
      for e in ["dev", "prod"] : [
        for s in concat(tolist(data.aws_iam_policy_document.apply_edge[e].statement), tolist(data.aws_iam_policy_document.apply_cdn[e].statement)) :
        length(s.condition) > 0 || !anytrue([for a in s.actions : contains(["cognito-idp:*", "apigateway:*"], a)])
        if s.effect == "Allow"
      ]
    ]))
    error_message = "cognito-idp:* and apigateway:* must never be allowed without a tag condition."
  }

  # Cognito user data plane denied; pool, client and group administration is not named
  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_guardrails[e].statement :
        s.sid == "DenyCognitoUserDataPlane" && s.effect == "Deny" &&
        length(setsubtract(toset(["cognito-idp:Admin*", "cognito-idp:ListUsers", "cognito-idp:SignUp"]), s.actions)) == 0 &&
        !anytrue([for a in s.actions : contains(["cognito-idp:CreateGroup", "cognito-idp:UpdateGroup", "cognito-idp:DeleteGroup", "cognito-idp:CreateUserPoolClient", "cognito-idp:UpdateUserPool", "cognito-idp:CreateUserPool"], a)])
      ])
    ])
    error_message = "cognito-idp:Admin*, ListUsers and SignUp must be denied, without denying pool, client or group administration."
  }

  # The Environment tag of an API cannot be rewritten through /tags
  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_guardrails[e].statement :
        s.sid == "DenyApiGatewayEnvironmentTagChange" && s.effect == "Deny" &&
        alltrue([for r in s.resources : strcontains(r, "::/tags/")]) &&
        anytrue([for c in s.condition : c.variable == "aws:TagKeys" && toset(c.values) == toset(["Environment"])])
      ])
    ])
    error_message = "Writing the Environment tag through API Gateway /tags must be denied."
  }

  # CloudFront and Cognito resources are covered by the cross-environment retagging guard
  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_guardrails[e].statement :
        s.sid == "DenyForeignEnvironmentTagging" &&
        length(setsubtract(toset(["cloudfront:TagResource", "cloudfront:UntagResource", "cognito-idp:TagResource", "cognito-idp:UntagResource"]), s.actions)) == 0
      ])
    ])
    error_message = "Retagging CloudFront and Cognito resources of another environment must be denied."
  }

  # CloudFront: the wildcard is no longer on the whole account, only on tagged distributions and on non-taggable policies
  assert {
    condition = alltrue(flatten([
      for e in ["dev", "prod"] : [
        for s in data.aws_iam_policy_document.apply_cdn[e].statement :
        !contains(s.resources, "arn:aws:cloudfront::123456789012:*")
        if startswith(s.sid, "CloudFront")
      ]
    ]))
    error_message = "CloudFront must not be allowed on every resource of the account."
  }
}

# EN-13-AC2 (F4): dev can create and read the non-taggable CloudFront resources, only prod can update, delete or publish them
run "en13_ac2_dev_cannot_update_cloudfront_supporting" {
  command = plan

  # Both roles: Create / Describe / Get / List only, never an Update, Delete or Publish, on every supporting resource type
  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_cdn[e].statement :
        s.sid == "CloudFrontSupportingRead" && s.effect == "Allow" && length(s.condition) == 0 &&
        toset(s.actions) == toset(["cloudfront:Create*", "cloudfront:Describe*", "cloudfront:Get*", "cloudfront:List*"]) &&
        toset(s.resources) == toset([
          "arn:aws:cloudfront::123456789012:cache-policy/*",
          "arn:aws:cloudfront::123456789012:origin-access-control/*",
          "arn:aws:cloudfront::123456789012:origin-request-policy/*",
          "arn:aws:cloudfront::123456789012:response-headers-policy/*",
        ])
      ])
    ])
    error_message = "Both apply roles must get Create*, Describe*, Get* and List* only on cache, origin access control, origin request and response headers policies."
  }

  # Dev: no Allow reaches a supporting resource with anything but the read statement, and no wildcard covers them
  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.apply_cdn["dev"].statement :
      s.sid == "CloudFrontSupportingRead" ||
      !anytrue([for r in s.resources : anytrue([for t in ["cache-policy", "origin-access-control", "origin-request-policy", "response-headers-policy"] : strcontains(r, ":${t}/")])])
      if s.effect == "Allow"
    ])
    error_message = "The dev apply role must not hold any statement on CloudFront supporting resources other than CloudFrontSupportingRead."
  }

  assert {
    condition = !anytrue([
      for s in data.aws_iam_policy_document.apply_cdn["dev"].statement :
      anytrue([for a in s.actions : anytrue([for p in ["cloudfront:Update", "cloudfront:Delete", "cloudfront:Publish"] : startswith(a, p)]) || a == "cloudfront:*"]) &&
      anytrue([for r in s.resources : !strcontains(r, "function/") && !strcontains(r, ":distribution/")])
      if s.effect == "Allow"
    ])
    error_message = "The dev apply role must not be allowed Update*, Delete*, Publish* or cloudfront:* outside distributions (tag-conditioned) and its own functions."
  }

  # Prod: the write statement exists, on the same resources, without the read-only restriction
  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.apply_cdn["prod"].statement :
      s.sid == "CloudFrontSupportingWrite" && s.effect == "Allow" &&
      toset(s.actions) == toset(["cloudfront:Delete*", "cloudfront:Publish*", "cloudfront:Update*"]) &&
      toset(s.resources) == toset([
        "arn:aws:cloudfront::123456789012:cache-policy/*",
        "arn:aws:cloudfront::123456789012:origin-access-control/*",
        "arn:aws:cloudfront::123456789012:origin-request-policy/*",
        "arn:aws:cloudfront::123456789012:response-headers-policy/*",
      ])
    ])
    error_message = "The prod apply role must be allowed Update*, Delete* and Publish* on the supporting CloudFront resources."
  }

  assert {
    condition     = !anytrue([for s in data.aws_iam_policy_document.apply_cdn["dev"].statement : s.sid == "CloudFrontSupportingWrite"])
    error_message = "CloudFrontSupportingWrite must not exist in the dev apply role."
  }

  # Functions stay name-scoped to the environment
  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_cdn[e].statement :
        s.sid == "CloudFrontFunctions" && toset(s.resources) == toset(["arn:aws:cloudfront::123456789012:function/sc-${e}-*"])
      ])
    ])
    error_message = "CloudFront functions must be scoped by sc-<env>-."
  }
}

# EN-13-AC2 (F4): Bedrock guardrails and knowledge bases are created and written only with the Environment tag
run "en13_ac2_bedrock_writes_tag_scoped" {
  command = plan

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      !anytrue([
        for s in data.aws_iam_policy_document.apply_edge[e].statement :
        anytrue([for a in s.actions : startswith(a, "bedrock:") && endswith(a, "*")])
        if s.effect == "Allow"
      ])
    ])
    error_message = "No bedrock wildcard action may be allowed."
  }

  # Every Allow that writes (Create / Update / Delete / Tag / Start) is tag-conditioned
  assert {
    condition = alltrue(flatten([
      for e in ["dev", "prod"] : [
        for s in data.aws_iam_policy_document.apply_edge[e].statement :
        anytrue([
          for c in s.condition :
          c.test == "StringEquals" && contains(["aws:ResourceTag/Environment", "aws:RequestTag/Environment"], c.variable) && toset(c.values) == toset([e])
        ])
        if s.effect == "Allow" && anytrue([for a in s.actions : startswith(a, "bedrock:") && anytrue([for p in ["Create", "Update", "Delete", "Tag", "Untag", "Start"] : startswith(a, "bedrock:${p}")])])
      ]
    ]))
    error_message = "Every Bedrock write must be conditioned on the Environment tag of the role."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_edge[e].statement :
        s.sid == "BedrockManage" && length(setintersection(toset(s.actions), toset(["bedrock:UpdateGuardrail", "bedrock:DeleteGuardrail", "bedrock:UpdateKnowledgeBase", "bedrock:DeleteKnowledgeBase", "bedrock:TagResource"]))) == 5 &&
        anytrue([for c in s.condition : c.test == "StringEquals" && c.variable == "aws:ResourceTag/Environment" && toset(c.values) == toset([e])]) &&
        alltrue([for r in s.resources : strcontains(r, ":guardrail/") || strcontains(r, ":knowledge-base/")])
      ]) &&
      anytrue([
        for s in data.aws_iam_policy_document.apply_edge[e].statement :
        s.sid == "BedrockTagOnCreate" && toset(s.actions) == toset(["bedrock:TagResource"]) && !contains(s.resources, "*") &&
        anytrue([for c in s.condition : c.variable == "aws:RequestTag/Environment" && toset(c.values) == toset([e])])
      ])
    ])
    error_message = "Update, Delete and Tag of guardrails and knowledge bases must need the Environment resource tag and be scoped to their ARNs."
  }

  # Retagging across environments is denied for Bedrock too
  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_guardrails[e].statement :
        s.sid == "DenyForeignEnvironmentTagging" && s.effect == "Deny" &&
        length(setsubtract(toset(["bedrock:TagResource", "bedrock:UntagResource"]), s.actions)) == 0
      ])
    ])
    error_message = "bedrock:TagResource and UntagResource must be covered by the cross-environment retagging guard."
  }

  # The apply roles do not invoke models or call the runtime
  assert {
    condition = !anytrue(flatten([
      for e in ["dev", "prod"] : [
        for s in data.aws_iam_policy_document.apply_edge[e].statement :
        anytrue([for a in s.actions : anytrue([for p in ["bedrock:Invoke", "bedrock:Retrieve", "bedrock:ApplyGuardrail"] : startswith(a, p)])])
        if s.effect == "Allow"
      ]
    ]))
    error_message = "The apply roles must not be allowed to invoke models or use the Bedrock runtime."
  }
}

# EN-13-AC2: the edge and cdn policies stay under the 6144 characters of a managed policy (statement JSON as a proxy)
run "en13_ac2_apply_edge_and_cdn_policies_under_size_limit" {
  command = plan

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      length(jsonencode(data.aws_iam_policy_document.apply_edge[e].statement)) < 6144 &&
      length(jsonencode(data.aws_iam_policy_document.apply_cdn[e].statement)) < 6144
    ])
    error_message = "The edge and cdn apply policies must stay under 6144 characters."
  }
}

# EN-13-AC2 (F8): event source mappings can only be created, updated or deleted for a function of the environment
run "en13_ac2_event_source_mapping_delete_tied_to_environment_function" {
  command = plan

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_compute[e].statement :
        s.sid == "LambdaEventSourceMappingsWrite" && s.effect == "Allow" &&
        toset(s.actions) == toset(["lambda:CreateEventSourceMapping", "lambda:DeleteEventSourceMapping", "lambda:UpdateEventSourceMapping"]) &&
        anytrue([
          for c in s.condition :
          c.test == "ArnLike" && c.variable == "lambda:FunctionArn" && alltrue([for v in c.values : strcontains(v, "function:sc-${e}-")])
        ])
      ])
    ])
    error_message = "Create, Update and DeleteEventSourceMapping must be conditioned on lambda:FunctionArn of the environment."
  }

  assert {
    condition = !anytrue(flatten([
      for e in ["dev", "prod"] : [
        for s in data.aws_iam_policy_document.apply_compute[e].statement :
        contains(s.actions, "lambda:DeleteEventSourceMapping")
        if s.effect == "Allow" && s.sid != "LambdaEventSourceMappingsWrite"
      ]
    ]))
    error_message = "lambda:DeleteEventSourceMapping must not be allowed outside the conditioned statement."
  }
}

# EN-13-AC2: nothing in the policies of an environment names the other environment
run "en13_ac2_no_cross_environment_reference" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for e, o in { dev = "prod", prod = "dev" } : [
        for d in [
          data.aws_iam_policy_document.apply_state[e],
          data.aws_iam_policy_document.apply_iam[e],
          data.aws_iam_policy_document.apply_compute[e],
          data.aws_iam_policy_document.apply_data[e],
          data.aws_iam_policy_document.apply_edge[e],
          data.aws_iam_policy_document.apply_cdn[e],
          ] : [
          for s in d.statement :
          alltrue([for r in s.resources : !strcontains(r, "sc-${o}-") && !strcontains(r, "/smartcampus/${o}/") && !strcontains(r, "/${o}/")])
        ]
      ]
    ]))
    error_message = "An environment's allow policies must not reference the resources or state prefix of the other environment."
  }
}

# =====================================================================================================================
# EN-13-AC3: permissions boundary required, and protected
# =====================================================================================================================

# EN-13-AC3: the boundaries exist under the names the policies reference
run "en13_ac3_boundaries_named_as_referenced" {
  command = plan

  assert {
    condition     = aws_iam_policy.ci_boundary.name == "sc-ci-boundary"
    error_message = "The ci boundary must be named <prefix>-ci-boundary."
  }

  # F1: one workload boundary per environment
  assert {
    condition     = toset(keys(aws_iam_policy.workload_boundary)) == toset(["dev", "prod"])
    error_message = "There must be exactly one workload boundary per environment."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      aws_iam_policy.workload_boundary[e].name == "sc-${e}-workload-boundary"
    ])
    error_message = "The workload boundaries must be named <prefix>-<env>-workload-boundary."
  }
}

# EN-13-AC3: CreateRole is only allowed with the workload boundary, on roles of the environment
run "en13_ac3_create_role_requires_workload_boundary" {
  command = plan

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_iam[e].statement :
        s.sid == "RoleCreateWithWorkloadBoundary" && s.effect == "Allow" &&
        toset(s.actions) == toset(["iam:CreateRole", "iam:PutRolePermissionsBoundary"]) &&
        toset(s.resources) == toset(["arn:aws:iam::123456789012:role/sc-${e}-*"]) &&
        anytrue([
          for c in s.condition :
          c.test == "StringEquals" && c.variable == "iam:PermissionsBoundary" &&
          toset(c.values) == toset(["arn:aws:iam::123456789012:policy/sc-${e}-workload-boundary"])
        ])
      ])
    ])
    error_message = "iam:CreateRole and iam:PutRolePermissionsBoundary must be allowed only on sc-<env>-* roles with iam:PermissionsBoundary equal to the workload boundary OF THAT ENVIRONMENT."
  }

  assert {
    condition = alltrue(flatten([
      for e in ["dev", "prod"] : [
        for d in [
          data.aws_iam_policy_document.apply_state[e],
          data.aws_iam_policy_document.apply_iam[e],
          data.aws_iam_policy_document.apply_compute[e],
          data.aws_iam_policy_document.apply_data[e],
          data.aws_iam_policy_document.apply_edge[e],
          data.aws_iam_policy_document.apply_cdn[e],
          ] : [
          for s in d.statement :
          anytrue([
            for c in s.condition :
            c.test == "StringEquals" && c.variable == "iam:PermissionsBoundary" &&
            toset(c.values) == toset(["arn:aws:iam::123456789012:policy/sc-${e}-workload-boundary"])
          ])
          if s.effect == "Allow" && length(setintersection(s.actions, toset([
            "iam:CreateRole", "iam:PutRolePermissionsBoundary", "iam:AttachRolePolicy", "iam:PutRolePolicy", "iam:DetachRolePolicy", "iam:DeleteRolePolicy",
          ]))) > 0
        ]
      ]
    ]))
    error_message = "Every Allow of a role creation or role policy action must be conditioned on the workload boundary."
  }
}

# EN-13-AC3 (F1): creating a role or replacing a boundary with anything but the boundary of the environment is denied
run "en13_ac3_boundary_replacement_denied" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for e in ["dev", "prod"] : [
        for d in [
          data.aws_iam_policy_document.apply_guardrails[e],
          data.aws_iam_policy_document.workload_boundary[e],
        ] :
        anytrue([
          for s in d.statement :
          s.sid == "DenyBoundaryReplace" && s.effect == "Deny" &&
          toset(s.actions) == toset(["iam:CreateRole", "iam:PutRolePermissionsBoundary"]) &&
          toset(s.resources) == toset(["arn:aws:iam::123456789012:role/*"]) &&
          anytrue([
            for c in s.condition :
            c.test == "StringNotEquals" && c.variable == "iam:PermissionsBoundary" &&
            toset(c.values) == toset(["arn:aws:iam::123456789012:policy/sc-${e}-workload-boundary"])
          ])
        ])
      ]
    ]))
    error_message = "The apply guardrails and the workload boundary of an environment must deny any boundary other than the boundary of that environment."
  }

  # The ci boundary allows either environment boundary (each apply role is narrowed by its own Deny)
  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.ci_boundary.statement :
      s.sid == "DenyBoundaryReplace" && s.effect == "Deny" &&
      toset(s.actions) == toset(["iam:CreateRole", "iam:PutRolePermissionsBoundary"]) &&
      anytrue([
        for c in s.condition :
        c.test == "StringNotEquals" && c.variable == "iam:PermissionsBoundary" &&
        toset(c.values) == toset(["arn:aws:iam::123456789012:policy/sc-dev-workload-boundary", "arn:aws:iam::123456789012:policy/sc-prod-workload-boundary"])
      ])
    ])
    error_message = "The ci boundary must deny any boundary other than the two workload boundaries."
  }

  # A dev apply role cannot create a role with the prod boundary, nor the reverse
  assert {
    condition = alltrue([
      for e, o in { dev = "prod", prod = "dev" } :
      alltrue([
        for s in data.aws_iam_policy_document.apply_iam[e].statement :
        !anytrue([
          for c in s.condition :
          c.variable == "iam:PermissionsBoundary" && contains(c.values, "arn:aws:iam::123456789012:policy/sc-${o}-workload-boundary")
        ])
      ])
    ])
    error_message = "An apply role must never reference the workload boundary of the other environment."
  }
}

# EN-13-AC3: the boundaries can neither be modified nor removed from a role
run "en13_ac3_boundary_cannot_be_modified_or_removed" {
  command = plan

  assert {
    condition = alltrue([
      for d in [
        data.aws_iam_policy_document.apply_guardrails["dev"],
        data.aws_iam_policy_document.apply_guardrails["prod"],
        data.aws_iam_policy_document.ci_boundary,
        data.aws_iam_policy_document.workload_boundary["dev"],
        data.aws_iam_policy_document.workload_boundary["prod"],
      ] :
      anytrue([
        for s in d.statement :
        s.sid == "DenyBoundaryPolicyTampering" && s.effect == "Deny" &&
        toset(s.actions) == toset(["iam:CreatePolicyVersion", "iam:DeletePolicy", "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion"]) &&
        toset(s.resources) == toset(["arn:aws:iam::123456789012:policy/sc-ci-boundary", "arn:aws:iam::123456789012:policy/sc-dev-workload-boundary", "arn:aws:iam::123456789012:policy/sc-prod-workload-boundary"])
      ])
    ])
    error_message = "Creating a version of, deleting or re-defaulting a boundary policy must be denied on the ci boundary and both workload boundaries (they sit under the sc-<env>-* policy names)."
  }

  assert {
    condition = alltrue([
      for d in [
        data.aws_iam_policy_document.apply_guardrails["dev"],
        data.aws_iam_policy_document.apply_guardrails["prod"],
        data.aws_iam_policy_document.ci_boundary,
        data.aws_iam_policy_document.workload_boundary["dev"],
        data.aws_iam_policy_document.workload_boundary["prod"],
      ] :
      anytrue([
        for s in d.statement :
        s.sid == "DenyBoundaryRemoval" && s.effect == "Deny" && toset(s.actions) == toset(["iam:DeleteRolePermissionsBoundary"]) &&
        toset(s.resources) == toset(["arn:aws:iam::123456789012:role/*"])
      ])
    ])
    error_message = "iam:DeleteRolePermissionsBoundary must be denied on every role."
  }

  assert {
    condition = alltrue(flatten([
      for e in ["dev", "prod"] : [
        for d in [
          data.aws_iam_policy_document.apply_state[e],
          data.aws_iam_policy_document.apply_iam[e],
          data.aws_iam_policy_document.apply_compute[e],
          data.aws_iam_policy_document.apply_data[e],
          data.aws_iam_policy_document.apply_edge[e],
          data.aws_iam_policy_document.apply_cdn[e],
          ] : [
          for s in d.statement :
          !contains(s.resources, "arn:aws:iam::123456789012:policy/sc-ci-boundary") && !contains(s.resources, "arn:aws:iam::123456789012:policy/sc-dev-workload-boundary") && !contains(s.resources, "arn:aws:iam::123456789012:policy/sc-prod-workload-boundary")
          if s.effect == "Allow"
        ]
      ]
    ]))
    error_message = "No Allow statement may name a boundary policy."
  }
}

# EN-13-AC3: the CI identity cannot be rewritten by the CI roles
run "en13_ac3_ci_boundary_protects_ci_identity" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.ci_boundary.statement :
      s.sid == "DenyCiRoleTampering" && s.effect == "Deny" &&
      toset(s.resources) == toset(["arn:aws:iam::123456789012:role/sc-gha-*"]) &&
      length(setsubtract(toset(["iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:DeleteRole"]), s.actions)) == 0
    ])
    error_message = "The ci boundary must deny changes to the sc-gha-* roles, including their trust policy."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.ci_boundary.statement :
      s.sid == "DenyCiPolicyTampering" && s.effect == "Deny" &&
      toset(s.resources) == toset(["arn:aws:iam::123456789012:policy/sc-gha-*"]) &&
      contains(s.actions, "iam:CreatePolicyVersion")
    ])
    error_message = "The ci boundary must deny changes to the sc-gha-* policies."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.ci_boundary.statement :
      s.sid == "DenyOidcProviderTampering" && s.effect == "Deny" &&
      toset(s.resources) == toset(["arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"]) &&
      contains(s.actions, "iam:DeleteOpenIDConnectProvider") && contains(s.actions, "iam:UpdateOpenIDConnectProviderThumbprint")
    ])
    error_message = "The ci boundary must deny changes to the OIDC provider."
  }
}

# EN-13-AC3: PassRole is scoped to the roles of the environment and to named services
run "en13_ac3_pass_role_scoped" {
  command = plan

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_iam[e].statement :
        s.sid == "PassRoleToPlatformServices" && s.effect == "Allow" && toset(s.actions) == toset(["iam:PassRole"]) &&
        toset(s.resources) == toset(["arn:aws:iam::123456789012:role/sc-${e}-*"]) &&
        anytrue([
          for c in s.condition :
          c.test == "StringEquals" && c.variable == "iam:PassedToService" &&
          contains(c.values, "lambda.amazonaws.com") && alltrue([for v in c.values : endswith(v, ".amazonaws.com")])
        ])
      ])
    ])
    error_message = "iam:PassRole must be limited to sc-<env>-* roles and conditioned on iam:PassedToService."
  }

  assert {
    condition = alltrue(flatten([
      for e in ["dev", "prod"] : [
        for d in [
          data.aws_iam_policy_document.apply_state[e],
          data.aws_iam_policy_document.apply_compute[e],
          data.aws_iam_policy_document.apply_data[e],
          data.aws_iam_policy_document.apply_edge[e],
          data.aws_iam_policy_document.apply_cdn[e],
          data.aws_iam_policy_document.apply_guardrails[e],
          ] : [
          for s in d.statement : !contains(s.actions, "iam:PassRole")
        ]
      ]
    ]))
    error_message = "Only the apply_iam policy may mention iam:PassRole."
  }
}

# EN-13-AC3: IAM roles and policies can only be managed under the environment prefix
run "en13_ac3_iam_resources_scoped_by_env_prefix" {
  command = plan

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      alltrue([
        for s in data.aws_iam_policy_document.apply_iam[e].statement :
        alltrue([
          for r in s.resources :
          r == "arn:aws:iam::123456789012:role/sc-${e}-*" || r == "arn:aws:iam::123456789012:policy/sc-${e}-*"
        ])
      ])
    ])
    error_message = "Roles and policies managed by an apply role must be named sc-<env>-*."
  }
}

# EN-13-AC3: a workload cannot escalate, reach account-level services or touch the state
run "en13_ac3_workload_boundary_denies_iam_and_state" {
  command = plan

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.workload_boundary[e].statement :
        s.sid == "DenyIam" && s.effect == "Deny" && toset(s.actions) == toset(["iam:*"]) && toset(s.resources) == toset(["*"])
      ])
    ])
    error_message = "The workload boundaries must deny every IAM action, including iam:PassRole."
  }

  assert {
    condition = alltrue(flatten([
      for e in ["dev", "prod"] : [
        for s in data.aws_iam_policy_document.workload_boundary[e].statement :
        s.effect == "Deny" || !anytrue([for a in s.actions : startswith(a, "iam:")])
      ]
    ]))
    error_message = "The workload boundaries must not allow any IAM action."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.workload_boundary[e].statement :
        s.sid == "DenyStateBackend" && s.effect == "Deny" && toset(s.actions) == toset(["kms:*", "s3:*"]) &&
        toset(s.resources) == toset([var.state_bucket_arn, "arn:aws:s3:::sc-tfstate-123456789012/*", var.state_kms_key_arn])
      ])
    ])
    error_message = "The workload boundaries must deny the state bucket and the state key."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.workload_boundary[e].statement :
        s.sid == "DenyAccountLevelServices" && s.effect == "Deny" && contains(s.actions, "organizations:*") && contains(s.actions, "billing:*")
      ])
    ])
    error_message = "The workload boundaries must deny the account-level services."
  }

  # F3: a role carrying the boundary cannot act through a federated identity (OIDC, SAML)
  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.workload_boundary[e].statement :
        s.sid == "DenyFederatedSessions" && s.effect == "Deny" && toset(s.actions) == toset(["*"]) && toset(s.resources) == toset(["*"]) &&
        anytrue([for c in s.condition : c.test == "Null" && c.variable == "aws:FederatedProvider" && toset(c.values) == toset(["false"])])
      ])
    ])
    error_message = "The workload boundaries must deny every action when aws:FederatedProvider is set."
  }
}

# EN-13-AC3 (F1): the ceiling of the workload boundary of an environment covers that environment only
run "en13_ac3_workload_boundary_ceiling_scoped_to_environment" {
  command = plan

  # Every Allow is scoped by sc-<env>-* ARNs, by the Environment tag, or is a known no-resource-level / AWS-owned case
  assert {
    condition = alltrue(flatten([
      for e in ["dev", "prod"] : [
        for s in data.aws_iam_policy_document.workload_boundary[e].statement :
        (
          alltrue([for r in s.resources : strcontains(r, "sc-${e}-") || strcontains(r, "/smartcampus/${e}/")]) ||
          anytrue([for c in s.condition : c.variable == "aws:ResourceTag/Environment" && toset(c.values) == toset([e])])
        )
        if s.effect == "Allow" && !contains(["CeilingWorkloadTracing", "CeilingWorkloadModels", "CeilingWorkloadMail"], s.sid)
      ]
    ]))
    error_message = "Every Allow of the workload boundary of an environment must be scoped to sc-<env>-* ARNs or to the Environment tag of that environment."
  }

  assert {
    condition = alltrue(flatten([
      for e, o in { dev = "prod", prod = "dev" } : [
        for s in data.aws_iam_policy_document.workload_boundary[e].statement :
        alltrue([for r in s.resources : !strcontains(r, "sc-${o}-") && !strcontains(r, "/smartcampus/${o}/")])
        if s.effect == "Allow"
      ]
    ]))
    error_message = "The workload boundary of an environment must not reference the resources of the other environment."
  }

  # No boundary-wide service wildcard on Resource "*", and no administration of keys
  assert {
    condition = alltrue(flatten([
      for e in ["dev", "prod"] : [
        for s in data.aws_iam_policy_document.workload_boundary[e].statement :
        !contains(s.resources, "*") || toset(s.actions) == toset(["xray:PutTelemetryRecords", "xray:PutTraceSegments"])
        if s.effect == "Allow"
      ]
    ]))
    error_message = "The only Resource \"*\" Allow of a workload boundary is the X-Ray trace write."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.workload_boundary[e].statement :
        s.sid == "CeilingWorkloadKeyUsage" && s.effect == "Allow" &&
        toset(s.actions) == toset(["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*"]) &&
        anytrue([for c in s.condition : c.test == "StringEquals" && c.variable == "aws:ResourceTag/Environment" && toset(c.values) == toset([e])])
      ]) &&
      anytrue([
        for s in data.aws_iam_policy_document.workload_boundary[e].statement :
        s.sid == "CeilingWorkloadLambdaInvoke" && toset(s.actions) == toset(["lambda:InvokeFunction"]) &&
        alltrue([for r in s.resources : strcontains(r, "function:sc-${e}-")])
      ]) &&
      !anytrue(flatten([
        for s in data.aws_iam_policy_document.workload_boundary[e].statement :
        [for a in s.actions : a == "kms:*" || a == "lambda:*"]
        if s.effect == "Allow"
      ]))
    ])
    error_message = "Keys are limited to Decrypt, Encrypt and GenerateDataKey* on Environment-tagged keys, Lambda to InvokeFunction on the environment functions."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.workload_boundary[e].statement :
        s.sid == "CeilingWorkloadParameters" && toset(s.actions) == toset(["ssm:GetParameter*"]) &&
        alltrue([for r in s.resources : strcontains(r, "/smartcampus/${e}/")])
      ])
    ])
    error_message = "SSM reads in a workload boundary must be limited to /smartcampus/<env>/."
  }
}

# =====================================================================================================================
# EN-13-AC4: no unjustified wildcard
# =====================================================================================================================

# EN-13-AC4: no Allow with the "*" or "iam:*" action in any policy generated by the module
run "en13_ac4_no_star_or_iam_wildcard_action_allowed" {
  command = plan

  assert {
    condition = alltrue([
      for s in concat(
        tolist(data.aws_iam_policy_document.plan_state.statement),
        tolist(data.aws_iam_policy_document.ci_boundary.statement),
        flatten([for e in ["dev", "prod"] : tolist(data.aws_iam_policy_document.workload_boundary[e].statement)]),
        flatten([
          for e in ["dev", "prod"] : [
            for d in [
              data.aws_iam_policy_document.apply_state[e],
              data.aws_iam_policy_document.apply_iam[e],
              data.aws_iam_policy_document.apply_compute[e],
              data.aws_iam_policy_document.apply_data[e],
              data.aws_iam_policy_document.apply_edge[e],
              data.aws_iam_policy_document.apply_cdn[e],
              data.aws_iam_policy_document.apply_guardrails[e],
            ] : tolist(d.statement)
          ]
        ])
      ) :
      !contains(s.actions, "*") && !contains(s.actions, "iam:*")
      if s.effect == "Allow"
    ])
    error_message = "No Allow statement may use the \"*\" or \"iam:*\" action."
  }

  assert {
    condition = alltrue([
      for s in concat(
        tolist(data.aws_iam_policy_document.plan_state.statement),
        tolist(data.aws_iam_policy_document.ci_boundary.statement),
        flatten([for e in ["dev", "prod"] : tolist(data.aws_iam_policy_document.workload_boundary[e].statement)]),
        flatten([
          for e in ["dev", "prod"] : [
            for d in [
              data.aws_iam_policy_document.apply_state[e],
              data.aws_iam_policy_document.apply_iam[e],
              data.aws_iam_policy_document.apply_compute[e],
              data.aws_iam_policy_document.apply_data[e],
              data.aws_iam_policy_document.apply_edge[e],
              data.aws_iam_policy_document.apply_cdn[e],
              data.aws_iam_policy_document.apply_guardrails[e],
            ] : tolist(d.statement)
          ]
        ])
      ) :
      alltrue([for a in s.actions : !strcontains(a, "*") || !startswith(a, "iam:")])
      if s.effect == "Allow"
    ])
    error_message = "IAM actions must be listed one by one in every Allow statement."
  }

  assert {
    condition = alltrue([
      for s in concat(
        tolist(data.aws_iam_policy_document.plan_state.statement),
        flatten([
          for e in ["dev", "prod"] : [
            for d in [
              data.aws_iam_policy_document.apply_state[e],
              data.aws_iam_policy_document.apply_iam[e],
              data.aws_iam_policy_document.apply_compute[e],
              data.aws_iam_policy_document.apply_data[e],
              data.aws_iam_policy_document.apply_edge[e],
              data.aws_iam_policy_document.apply_cdn[e],
            ] : tolist(d.statement)
          ]
        ])
      ) :
      length(coalesce(s.not_actions, [])) == 0 && length(coalesce(s.not_resources, [])) == 0
      if s.effect == "Allow"
    ])
    error_message = "Identity policies must not use NotAction or NotResource in an Allow statement."
  }
}

# EN-13-AC4: Resource "*" in an Allow is limited to a closed allow-list (each entry carries an inline Checkov skip)
run "en13_ac4_resource_star_only_allowlisted" {
  command = plan

  assert {
    condition = length(setsubtract(
      toset(flatten([
        [for s in data.aws_iam_policy_document.plan_state.statement : "plan_state/${s.sid}" if s.effect == "Allow" && contains(s.resources, "*")],
        [for s in data.aws_iam_policy_document.ci_boundary.statement : "ci_boundary/${s.sid}" if s.effect == "Allow" && contains(s.resources, "*")],
        [
          for e in ["dev", "prod"] : [
            for s in data.aws_iam_policy_document.workload_boundary[e].statement : "workload_boundary/${s.sid}" if s.effect == "Allow" && contains(s.resources, "*")
          ]
        ],
        [
          for e in ["dev", "prod"] : [
            [for s in data.aws_iam_policy_document.apply_state[e].statement : "apply_state/${s.sid}" if s.effect == "Allow" && contains(s.resources, "*")],
            [for s in data.aws_iam_policy_document.apply_iam[e].statement : "apply_iam/${s.sid}" if s.effect == "Allow" && contains(s.resources, "*")],
            [for s in data.aws_iam_policy_document.apply_compute[e].statement : "apply_compute/${s.sid}" if s.effect == "Allow" && contains(s.resources, "*")],
            [for s in data.aws_iam_policy_document.apply_data[e].statement : "apply_data/${s.sid}" if s.effect == "Allow" && contains(s.resources, "*")],
            [for s in data.aws_iam_policy_document.apply_edge[e].statement : "apply_edge/${s.sid}" if s.effect == "Allow" && contains(s.resources, "*")],
            [for s in data.aws_iam_policy_document.apply_cdn[e].statement : "apply_cdn/${s.sid}" if s.effect == "Allow" && contains(s.resources, "*")],
            [for s in data.aws_iam_policy_document.apply_guardrails[e].statement : "apply_guardrails/${s.sid}" if s.effect == "Allow" && contains(s.resources, "*")],
          ]
        ],
      ])),
      toset([
        "ci_boundary/CeilingReadOnly",
        "ci_boundary/CeilingPlatformServices",
        "workload_boundary/CeilingWorkloadTracing",
        "apply_compute/NoResourceLevel",
        "apply_data/KeyCreate",
        "apply_data/NoResourceLevel",
        "apply_edge/CognitoCreate",
        "apply_edge/BedrockCreate",
      ])
    )) == 0
    error_message = "Resource \"*\" in an Allow statement is only accepted in the documented allow-list: the boundary ceilings and the actions without resource-level support."
  }
}

# EN-13-AC4: the actions allowed on Resource "*" in the apply policies form a closed list of calls without resource-level support
run "en13_ac4_resource_star_actions_are_closed_list" {
  command = plan

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_compute[e].statement :
        s.sid == "NoResourceLevel" && s.effect == "Allow" && toset(s.actions) == toset([
          "cloudwatch:DescribeAlarms",
          "logs:CreateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:DescribeLogGroups",
          "logs:DescribeResourcePolicies",
          "logs:GetLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:UpdateLogDelivery",
        ])
      ])
    ])
    error_message = "The compute NoResourceLevel statement must list exactly the actions without resource-level support."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_data[e].statement :
        s.sid == "NoResourceLevel" && s.effect == "Allow" && toset(s.actions) == toset(["kms:ListAliases", "ssm:DescribeParameters"])
      ])
    ])
    error_message = "The data NoResourceLevel statement must list exactly the actions without resource-level support."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_data[e].statement :
        s.sid == "KeyCreate" && s.effect == "Allow" && toset(s.actions) == toset(["kms:CreateKey"]) &&
        anytrue([
          for c in s.condition :
          c.test == "StringEquals" && c.variable == "aws:RequestTag/Environment" && toset(c.values) == toset([e])
        ])
      ])
    ])
    error_message = "kms:CreateKey on Resource \"*\" must be conditioned on the Environment request tag."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_edge[e].statement :
        s.sid == "CognitoCreate" && s.effect == "Allow" && toset(s.actions) == toset(["cognito-idp:CreateUserPool"]) &&
        anytrue([
          for c in s.condition :
          c.test == "StringEquals" && c.variable == "aws:RequestTag/Environment" && toset(c.values) == toset([e])
        ])
      ])
    ])
    error_message = "cognito-idp:CreateUserPool on Resource \"*\" must be conditioned on the Environment request tag."
  }

  assert {
    condition = alltrue([
      for e in ["dev", "prod"] :
      anytrue([
        for s in data.aws_iam_policy_document.apply_edge[e].statement :
        s.sid == "BedrockCreate" && s.effect == "Allow" && toset(s.actions) == toset(["bedrock:CreateGuardrail", "bedrock:CreateKnowledgeBase"]) &&
        anytrue([
          for c in s.condition :
          c.test == "StringEquals" && c.variable == "aws:RequestTag/Environment" && toset(c.values) == toset([e])
        ])
      ])
    ])
    error_message = "bedrock:CreateGuardrail and CreateKnowledgeBase on Resource \"*\" must be conditioned on the Environment request tag."
  }
}

# =====================================================================================================================
# EN-13-AC5: no long-lived credential
# =====================================================================================================================

# EN-13-AC5: creating users, access keys, passwords and signing material is denied everywhere
run "en13_ac5_long_lived_credentials_denied" {
  command = plan

  assert {
    condition = alltrue([
      for d in [
        data.aws_iam_policy_document.apply_guardrails["dev"],
        data.aws_iam_policy_document.apply_guardrails["prod"],
        data.aws_iam_policy_document.ci_boundary,
      ] :
      anytrue([
        for s in d.statement :
        s.sid == "DenyLongLivedCredentials" && s.effect == "Deny" &&
        toset(s.resources) == toset(["arn:aws:iam::123456789012:user/*"]) &&
        length(setsubtract(
          toset(["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile", "iam:UpdateLoginProfile", "iam:CreateServiceSpecificCredential", "iam:UploadSSHPublicKey", "iam:UploadSigningCertificate"]),
          s.actions
        )) == 0
      ])
    ])
    error_message = "iam:CreateUser, iam:CreateAccessKey and the other credential-creating actions must be denied in the apply guardrails and in the ci boundary."
  }
}

# EN-13-AC5: no policy of the module grants a credential-creating action
run "en13_ac5_no_allow_of_credential_actions" {
  command = plan

  assert {
    condition = alltrue([
      for s in concat(
        tolist(data.aws_iam_policy_document.plan_state.statement),
        tolist(data.aws_iam_policy_document.ci_boundary.statement),
        flatten([for e in ["dev", "prod"] : tolist(data.aws_iam_policy_document.workload_boundary[e].statement)]),
        flatten([
          for e in ["dev", "prod"] : [
            for d in [
              data.aws_iam_policy_document.apply_state[e],
              data.aws_iam_policy_document.apply_iam[e],
              data.aws_iam_policy_document.apply_compute[e],
              data.aws_iam_policy_document.apply_data[e],
              data.aws_iam_policy_document.apply_edge[e],
              data.aws_iam_policy_document.apply_cdn[e],
              data.aws_iam_policy_document.apply_guardrails[e],
            ] : tolist(d.statement)
          ]
        ])
      ) :
      length(setintersection(s.actions, toset([
        "iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile", "iam:UpdateLoginProfile",
        "iam:CreateServiceSpecificCredential", "iam:UploadSSHPublicKey", "iam:UploadSigningCertificate",
      ]))) == 0
      if s.effect == "Allow"
    ])
    error_message = "No Allow statement may grant an action that creates a long-lived credential."
  }
}

# =====================================================================================================================
# Variable validations
# =====================================================================================================================

# EN-13-AC2: rejects an invalid name_prefix
run "en13_ac2_rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Bad_Prefix"
  }

  expect_failures = [var.name_prefix]
}

# EN-13-AC1: rejects a repository with a wildcard (the sub claim is pinned verbatim)
run "en13_ac1_rejects_repository_wildcard" {
  command = plan

  variables {
    github_repository = "smart-campus-ai/*"
  }

  expect_failures = [var.github_repository]
}

# EN-13-AC1: rejects a repository that is not <owner>/<repo>
run "en13_ac1_rejects_repository_without_owner" {
  command = plan

  variables {
    github_repository = "smart-campus-ai"
  }

  expect_failures = [var.github_repository]
}

# EN-13-AC2: rejects an empty region list
run "en13_ac2_rejects_empty_allowed_regions" {
  command = plan

  variables {
    allowed_regions = []
  }

  expect_failures = [var.allowed_regions]
}

# EN-13-AC2: rejects a wildcard region
run "en13_ac2_rejects_wildcard_region" {
  command = plan

  variables {
    allowed_regions = ["eu-west-3", "us-*"]
  }

  expect_failures = [var.allowed_regions]
}

# EN-13-AC2: rejects a state bucket ARN with a key suffix or wildcard
run "en13_ac2_rejects_state_bucket_arn_with_key" {
  command = plan

  variables {
    state_bucket_arn = "arn:aws:s3:::sc-tfstate-123456789012/*"
  }

  expect_failures = [var.state_bucket_arn]
}

# EN-13-AC2: rejects a state key alias instead of a key ARN
run "en13_ac2_rejects_state_key_alias" {
  command = plan

  variables {
    state_kms_key_arn = "arn:aws:kms:eu-west-3:123456789012:alias/sc-tfstate"
  }

  expect_failures = [var.state_kms_key_arn]
}

# EN-13-AC1: rejects create_oidc_provider = false without the existing provider ARN
run "en13_ac1_rejects_missing_existing_provider_arn" {
  command = plan

  variables {
    create_oidc_provider = false
  }

  expect_failures = [var.existing_oidc_provider_arn]
}

# EN-13-AC1: rejects an existing provider ARN when the provider is created
run "en13_ac1_rejects_existing_provider_arn_when_creating" {
  command = plan

  variables {
    existing_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  }

  expect_failures = [var.existing_oidc_provider_arn]
}

# EN-13-AC1: rejects an existing provider ARN that is not the GitHub provider
run "en13_ac1_rejects_foreign_provider_arn" {
  command = plan

  variables {
    create_oidc_provider       = false
    existing_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/accounts.google.com"
  }

  expect_failures = [var.existing_oidc_provider_arn]
}

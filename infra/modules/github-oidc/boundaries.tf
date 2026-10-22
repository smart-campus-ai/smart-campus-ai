# Both documents are permissions boundaries, i.e. CEILINGS: they grant nothing by themselves, they cap what the identity
# policies of a role can grant. Service-level wildcards and Resource "*" therefore appear in the "Ceiling*" statements
# below and in no identity policy of this module.
#
# - ci-boundary: attached to the three CI roles. Ceiling = read-only everywhere + the services the platform stacks
#   deploy + role/policy management scoped to this account. Denies protect the boundaries, the CI identity itself and
#   forbid long-lived credentials.
# - <prefix>-<env>-workload-boundary (one per environment): must be attached to every role the apply role of that
#   environment creates (Lambda, Scheduler, API Gateway, Bedrock roles). Ceiling = the runtime actions of the
#   platform on <prefix>-<env>-* resources (and on Environment=<env> tagged keys), so a role of dev can never reach
#   prod data even if someone attaches a broad policy to it. IAM is denied entirely (a workload cannot escalate, not
#   even through iam:PassRole), as are the account-level services, the OpenTofu state and federated sessions.

# Permissions boundary = ceiling: service wildcards and PassRole grant nothing by themselves.
#trivy:ignore:AVD-AWS-0057
#trivy:ignore:AVD-AWS-0345
#trivy:ignore:AVD-AWS-0342
data "aws_iam_policy_document" "ci_boundary" {
  # checkov:skip=CKV_AWS_107: Permissions boundary ceiling, grants nothing by itself; the identity policies of the CI roles are scoped.
  # checkov:skip=CKV_AWS_108: Permissions boundary ceiling, grants nothing by itself; data-plane reads are denied on the plan role.
  # checkov:skip=CKV_AWS_109: Permissions boundary ceiling, grants nothing by itself; IAM actions are scoped to this account and boundary-conditioned in the roles.
  # checkov:skip=CKV_AWS_110: Permissions boundary ceiling, grants nothing by itself; privilege escalation is blocked by the workload boundary and explicit denies.
  # checkov:skip=CKV_AWS_111: Permissions boundary ceiling, grants nothing by itself; write access is constrained in the identity policies.
  # checkov:skip=CKV_AWS_287: Permissions boundary ceiling, grants nothing by itself.
  # checkov:skip=CKV_AWS_288: Permissions boundary ceiling, grants nothing by itself.
  # checkov:skip=CKV_AWS_289: Permissions boundary ceiling, grants nothing by itself.
  # checkov:skip=CKV_AWS_290: Permissions boundary ceiling, grants nothing by itself.
  # checkov:skip=CKV_AWS_355: Permissions boundary ceiling, grants nothing by itself.
  # checkov:skip=CKV_AWS_356: Permissions boundary ceiling, grants nothing by itself.
  statement {
    sid       = "CeilingReadOnly"
    effect    = "Allow"
    resources = ["*"]

    actions = ["*:Describe*", "*:Get*", "*:List*"]
  }

  statement {
    sid       = "CeilingPlatformServices"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "acm:*",
      "apigateway:*",
      "bedrock:*",
      "cloudfront:*",
      "cloudwatch:*",
      "cognito-idp:*",
      "dynamodb:*",
      "events:*",
      "kms:*",
      "lambda:*",
      "logs:*",
      "s3:*",
      "scheduler:*",
      "ses:*",
      "sns:*",
      "sqs:*",
      "ssm:*",
      "tag:*",
      "wafv2:*",
      "xray:*",
    ]
  }

  statement {
    sid    = "CeilingIam"
    effect = "Allow"

    actions = concat(
      local.iam_role_create_actions,
      local.iam_role_policy_actions,
      local.iam_role_manage_actions,
      local.iam_policy_actions,
      ["iam:PassRole"],
    )

    resources = concat(local.any_role_arns, ["${local.iam_arn_base}:policy/*"])
  }

  statement {
    sid       = "DenyBoundaryPolicyTampering"
    effect    = "Deny"
    resources = local.boundary_arns

    actions = [
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
    ]
  }

  statement {
    sid       = "DenyBoundaryRemoval"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = local.any_role_arns
  }

  statement {
    sid       = "DenyBoundaryReplace"
    effect    = "Deny"
    actions   = local.iam_role_create_actions
    resources = local.any_role_arns

    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = local.workload_boundary_arn_list
    }
  }

  statement {
    sid       = "DenyCiRoleTampering"
    effect    = "Deny"
    actions   = local.ci_identity_role_actions
    resources = local.ci_role_arns
  }

  statement {
    sid       = "DenyCiPolicyTampering"
    effect    = "Deny"
    actions   = local.ci_identity_policy_actions
    resources = local.ci_policy_arns
  }

  statement {
    sid       = "DenyOidcProviderTampering"
    effect    = "Deny"
    actions   = local.oidc_provider_write_actions
    resources = [local.oidc_provider_arn]
  }

  statement {
    sid       = "DenyLongLivedCredentials"
    effect    = "Deny"
    actions   = local.credential_actions
    resources = local.any_user_arns
  }

  statement {
    sid       = "DenyAccountLevelServices"
    effect    = "Deny"
    actions   = local.account_level_actions
    resources = ["*"]
  }
}

# Permissions boundary = ceiling: service wildcards and PassRole grant nothing by themselves.
#trivy:ignore:AVD-AWS-0057
#trivy:ignore:AVD-AWS-0345
#trivy:ignore:AVD-AWS-0342
data "aws_iam_policy_document" "workload_boundary" {
  # checkov:skip=CKV_AWS_107: Permissions boundary ceiling, grants nothing by itself; workload roles get scoped identity policies.
  # checkov:skip=CKV_AWS_108: Permissions boundary ceiling, grants nothing by itself.
  # checkov:skip=CKV_AWS_109: Permissions boundary ceiling, grants nothing by itself; IAM is denied entirely below.
  # checkov:skip=CKV_AWS_110: Permissions boundary ceiling, grants nothing by itself; IAM is denied entirely below.
  # checkov:skip=CKV_AWS_111: Permissions boundary ceiling, grants nothing by itself.
  # checkov:skip=CKV_AWS_287: Permissions boundary ceiling, grants nothing by itself.
  # checkov:skip=CKV_AWS_288: Permissions boundary ceiling, grants nothing by itself.
  # checkov:skip=CKV_AWS_289: Permissions boundary ceiling, grants nothing by itself.
  # checkov:skip=CKV_AWS_290: Permissions boundary ceiling, grants nothing by itself.
  # checkov:skip=CKV_AWS_355: Permissions boundary ceiling, grants nothing by itself.
  # checkov:skip=CKV_AWS_356: Permissions boundary ceiling, grants nothing by itself; the only Resource "*" is the X-Ray write, which has no resource-level support.
  for_each = local.environments

  # Name-scoped data plane of the environment. One statement: an action only ever matches the ARNs of its own service.
  statement {
    sid    = "CeilingWorkloadResources"
    effect = "Allow"

    actions = [
      "dynamodb:*",
      "events:*",
      "logs:*",
      "s3:*",
      "scheduler:*",
      "sns:*",
      "sqs:*",
    ]

    resources = concat(
      local.workload_arns[each.key].dynamodb_tables,
      local.workload_arns[each.key].events,
      local.workload_arns[each.key].log_groups,
      local.workload_arns[each.key].s3_buckets,
      local.workload_arns[each.key].scheduler,
      local.workload_arns[each.key].sns_topics,
      local.workload_arns[each.key].sqs_queues,
    )
  }

  statement {
    sid       = "CeilingWorkloadLambdaInvoke"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = local.workload_arns[each.key].lambda
  }

  # Keys are addressed by ID: data-key usage is limited to the keys tagged with the environment, never key
  # administration (no grants, no policy, no deletion).
  statement {
    sid       = "CeilingWorkloadKeyUsage"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*"]
    resources = local.workload_arns[each.key].kms_keys

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "CeilingWorkloadParameters"
    effect    = "Allow"
    actions   = ["ssm:GetParameter*"]
    resources = local.workload_arns[each.key].ssm_parameters
  }

  statement {
    sid       = "CeilingWorkloadMail"
    effect    = "Allow"
    actions   = ["ses:SendEmail", "ses:SendRawEmail", "ses:SendTemplatedEmail"]
    resources = local.workload_arns[each.key].ses
  }

  statement {
    sid       = "CeilingWorkloadModels"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = local.workload_arns[each.key].bedrock_models
  }

  # Knowledge bases and guardrails are addressed by ID: limited by the Environment tag.
  statement {
    sid       = "CeilingWorkloadKnowledge"
    effect    = "Allow"
    actions   = ["bedrock:ApplyGuardrail", "bedrock:Retrieve", "bedrock:RetrieveAndGenerate"]
    resources = local.workload_arns[each.key].bedrock_runtime

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "CeilingWorkloadUserLookup"
    effect    = "Allow"
    actions   = ["cognito-idp:AdminGetUser", "cognito-idp:AdminListGroupsForUser"]
    resources = local.workload_arns[each.key].cognito_pools

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  # No resource-level support: X-Ray trace writes.
  statement {
    sid       = "CeilingWorkloadTracing"
    effect    = "Allow"
    actions   = ["xray:PutTelemetryRecords", "xray:PutTraceSegments"]
    resources = ["*"]
  }

  # A role carrying this boundary can never be used through a federated identity (OIDC, SAML): the service roles of
  # the platform are assumed by service principals only. This caps a role created with a hostile trust policy
  # (F3, residual risk in ADR-0012: IAM has no condition key on the content of a trust policy).
  statement {
    sid       = "DenyFederatedSessions"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "Null"
      variable = "aws:FederatedProvider"
      values   = ["false"]
    }
  }

  # iam:PassRole is denied too: a workload role can never hand another role to a service.
  statement {
    sid       = "DenyIam"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = ["*"]
  }

  statement {
    sid       = "DenyAccountLevelServices"
    effect    = "Deny"
    actions   = local.account_level_actions
    resources = ["*"]
  }

  # ADR-0011: the state key cannot separate environments, so no workload may touch the state bucket or its key.
  statement {
    sid     = "DenyStateBackend"
    effect  = "Deny"
    actions = ["kms:*", "s3:*"]

    resources = [
      var.state_bucket_arn,
      local.state_objects_arn,
      var.state_kms_key_arn,
    ]
  }

  statement {
    sid       = "DenyBoundaryPolicyTampering"
    effect    = "Deny"
    resources = local.boundary_arns

    actions = [
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
    ]
  }

  statement {
    sid       = "DenyBoundaryRemoval"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = local.any_role_arns
  }

  statement {
    sid       = "DenyBoundaryReplace"
    effect    = "Deny"
    actions   = local.iam_role_create_actions
    resources = local.any_role_arns

    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.workload_boundary_arns[each.key]]
    }
  }
}

resource "aws_iam_policy" "ci_boundary" {
  name        = local.ci_boundary_name
  description = "Permissions boundary of the CI roles (plan and apply): caps what their policies can grant and protects the boundaries and the CI identity."
  policy      = data.aws_iam_policy_document.ci_boundary.json

  tags = merge(var.tags, { Name = local.ci_boundary_name })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_policy" "workload_boundary" {
  for_each = local.environments

  name        = local.workload_boundary_names[each.key]
  description = "Permissions boundary required on every role created by the ${each.key} apply role: runtime actions on ${local.env_prefix[each.key]}-* resources only, no IAM, no account-level services, no access to the OpenTofu state."
  policy      = data.aws_iam_policy_document.workload_boundary[each.key].json

  tags = merge(var.tags, { Name = local.workload_boundary_names[each.key], Environment = each.key })

  lifecycle {
    prevent_destroy = true
  }
}

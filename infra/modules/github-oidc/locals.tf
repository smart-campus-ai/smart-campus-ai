data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  arn_base = "arn:${data.aws_partition.current.partition}"

  iam_arn_base = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}"
}

# --- GitHub OIDC ---------------------------------------------------------------------------------------------------
locals {
  oidc_host = "token.actions.githubusercontent.com"

  oidc_audience = "sts.amazonaws.com"

  oidc_provider_arn = var.create_oidc_provider ? one(aws_iam_openid_connect_provider.github[*].arn) : var.existing_oidc_provider_arn

  # Only these two environments exist (ADR-0002). Adding one is a code change reviewed with the role policies.
  environments = toset(["dev", "prod"])

  other_environment = { for e in local.environments : e => one([for o in local.environments : o if o != e]) }

  env_prefix = { for e in local.environments : e => "${var.name_prefix}-${e}" }

  max_session_duration = 3600

  plan_sub = "repo:${var.github_repository}:pull_request"

  apply_sub = { for e in local.environments : e => "repo:${var.github_repository}:environment:${e}" }
}

# --- Names and ARNs known before apply (avoids dependency cycles between boundaries and roles) -----------------------
locals {
  plan_role_name = "${var.name_prefix}-gha-plan"

  apply_role_names = { for e in local.environments : e => "${var.name_prefix}-gha-apply-${e}" }

  ci_boundary_name = "${var.name_prefix}-ci-boundary"

  # One workload boundary per environment (ADR-0012): the ceiling of sc-dev-* roles never covers sc-prod-* resources.
  workload_boundary_names = { for e in local.environments : e => "${var.name_prefix}-${e}-workload-boundary" }

  ci_boundary_arn = "${local.iam_arn_base}:policy/${local.ci_boundary_name}"

  workload_boundary_arns = { for e, n in local.workload_boundary_names : e => "${local.iam_arn_base}:policy/${n}" }

  # Every boundary: the Denies that protect boundaries from tampering name all of them.
  boundary_arns = concat([local.ci_boundary_arn], [for e in sort(tolist(local.environments)) : local.workload_boundary_arns[e]])

  # The ci boundary lets a CI role create a role with the boundary of any environment; the apply roles are narrowed to
  # their own environment by their Deny.
  workload_boundary_arn_list = [for e in sort(tolist(local.environments)) : local.workload_boundary_arns[e]]

  # Every CI identity (roles and policies) is named <prefix>-gha-*; environment resources are <prefix>-<env>-*, so the
  # two name spaces never overlap and the apply roles cannot touch the CI identity.
  ci_role_arns = ["${local.iam_arn_base}:role/${var.name_prefix}-gha-*"]

  ci_policy_arns = ["${local.iam_arn_base}:policy/${var.name_prefix}-gha-*"]

  any_role_arns = ["${local.iam_arn_base}:role/*"]

  any_user_arns = ["${local.iam_arn_base}:user/*"]

  state_objects_arn = "${var.state_bucket_arn}/*"

  # F5: the plan role runs on any pull_request, so it only reads the dev state. Prod plans are computed inside the prod
  # apply job, behind the GitHub environment approval.
  plan_state_environment = "dev"

  plan_state_objects_arn = "${var.state_bucket_arn}/${local.plan_state_environment}/*"
}

# --- Action lists shared by the boundaries and the apply policies --------------------------------------------------
locals {
  iam_role_create_actions = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]

  iam_role_policy_actions = ["iam:AttachRolePolicy", "iam:DeleteRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy"]

  iam_role_manage_actions = [
    "iam:DeleteRole",
    "iam:GetRole",
    "iam:GetRolePolicy",
    "iam:ListAttachedRolePolicies",
    "iam:ListInstanceProfilesForRole",
    "iam:ListRolePolicies",
    "iam:ListRoleTags",
    "iam:TagRole",
    "iam:UntagRole",
    "iam:UpdateAssumeRolePolicy",
    "iam:UpdateRole",
    "iam:UpdateRoleDescription",
  ]

  iam_policy_actions = [
    "iam:CreatePolicy",
    "iam:CreatePolicyVersion",
    "iam:DeletePolicy",
    "iam:DeletePolicyVersion",
    "iam:GetPolicy",
    "iam:GetPolicyVersion",
    "iam:ListPolicyTags",
    "iam:ListPolicyVersions",
    "iam:SetDefaultPolicyVersion",
    "iam:TagPolicy",
    "iam:UntagPolicy",
  ]

  # Services a role created by the apply roles may be passed to (Lambda execution roles, Scheduler targets, API Gateway
  # CloudWatch role, Bedrock Knowledge Base role, EventBridge targets).
  passable_services = [
    "apigateway.amazonaws.com",
    "bedrock.amazonaws.com",
    "events.amazonaws.com",
    "lambda.amazonaws.com",
    "scheduler.amazonaws.com",
  ]

  # AC5: nothing the CI can do may create a long-lived credential.
  credential_actions = [
    "iam:CreateAccessKey",
    "iam:CreateLoginProfile",
    "iam:CreateServiceSpecificCredential",
    "iam:CreateUser",
    "iam:ResetServiceSpecificCredential",
    "iam:UpdateAccessKey",
    "iam:UpdateLoginProfile",
    "iam:UploadSigningCertificate",
    "iam:UploadSSHPublicKey",
  ]

  account_level_actions = [
    "account:*",
    "aws-portal:*",
    "billing:*",
    "invoicing:*",
    "organizations:*",
    "payments:*",
  ]

  # Changing any of these would let a CI role rewrite its own trust, its own boundary or the OIDC provider.
  ci_identity_role_actions = [
    "iam:AttachRolePolicy",
    "iam:DeleteRole",
    "iam:DeleteRolePolicy",
    "iam:DetachRolePolicy",
    "iam:PutRolePolicy",
    "iam:TagRole",
    "iam:UntagRole",
    "iam:UpdateAssumeRolePolicy",
    "iam:UpdateRole",
    "iam:UpdateRoleDescription",
  ]

  ci_identity_policy_actions = [
    "iam:CreatePolicyVersion",
    "iam:DeletePolicy",
    "iam:DeletePolicyVersion",
    "iam:SetDefaultPolicyVersion",
  ]

  # Resources addressed by a generated ID are separated by their Environment tag. Retagging is the way across, so the
  # apply guardrails deny it on every resource that already carries an Environment tag of another environment.
  tag_guarded_actions = [
    "bedrock:TagResource",
    "bedrock:UntagResource",
    "cloudfront:TagResource",
    "cloudfront:UntagResource",
    "cognito-idp:TagResource",
    "cognito-idp:UntagResource",
    "kms:TagResource",
    "kms:UntagResource",
  ]

  # F4: user data plane of Cognito. The apply roles manage pools, clients and groups, never the users inside them.
  cognito_user_data_actions = [
    "cognito-idp:Admin*",
    "cognito-idp:CreateUserImportJob",
    "cognito-idp:ListUsers",
    "cognito-idp:ListUsersInGroup",
    "cognito-idp:SignUp",
    "cognito-idp:StartUserImportJob",
  ]

  oidc_provider_write_actions = [
    "iam:AddClientIDToOpenIDConnectProvider",
    "iam:DeleteOpenIDConnectProvider",
    "iam:RemoveClientIDFromOpenIDConnectProvider",
    "iam:TagOpenIDConnectProvider",
    "iam:UntagOpenIDConnectProvider",
    "iam:UpdateOpenIDConnectProviderThumbprint",
  ]
}

# --- Per-environment resource ARNs (name-scoped by <prefix>-<env>-*) -----------------------------------------------
# Resources addressed by a generated ID (API Gateway, Cognito, CloudFront, KMS keys, SES identities, Bedrock) cannot be
# scoped by name: they are limited to the account and the allowed regions, and KMS keys additionally by the
# Environment tag. See ADR-0012 (residual risks).
locals {
  env_arns = {
    for e, p in local.env_prefix : e => {
      lambda_functions = [for r in var.allowed_regions : "${local.arn_base}:lambda:${r}:${local.account_id}:function:${p}-*"]
      lambda_layers    = [for r in var.allowed_regions : "${local.arn_base}:lambda:${r}:${local.account_id}:layer:${p}-*"]
      lambda_mappings  = [for r in var.allowed_regions : "${local.arn_base}:lambda:${r}:${local.account_id}:event-source-mapping:*"]
      dynamodb_tables  = [for r in var.allowed_regions : "${local.arn_base}:dynamodb:${r}:${local.account_id}:table/${p}-*"]
      sqs_queues       = [for r in var.allowed_regions : "${local.arn_base}:sqs:${r}:${local.account_id}:${p}-*"]
      sns_topics       = [for r in var.allowed_regions : "${local.arn_base}:sns:${r}:${local.account_id}:${p}-*"]
      event_rules      = flatten([for r in var.allowed_regions : ["${local.arn_base}:events:${r}:${local.account_id}:rule/${p}-*", "${local.arn_base}:events:${r}:${local.account_id}:event-bus/${p}-*"]])
      scheduler        = flatten([for r in var.allowed_regions : ["${local.arn_base}:scheduler:${r}:${local.account_id}:schedule/${p}-*/*", "${local.arn_base}:scheduler:${r}:${local.account_id}:schedule-group/${p}-*"]])
      log_groups       = flatten([for r in var.allowed_regions : ["${local.arn_base}:logs:${r}:${local.account_id}:log-group:/aws/lambda/${p}-*", "${local.arn_base}:logs:${r}:${local.account_id}:log-group:/aws/apigateway/${p}-*", "${local.arn_base}:logs:${r}:${local.account_id}:log-group:aws-waf-logs-${p}-*", "${local.arn_base}:logs:${r}:${local.account_id}:log-group:${p}-*"]])
      cw_alarms        = [for r in var.allowed_regions : "${local.arn_base}:cloudwatch:${r}:${local.account_id}:alarm:${p}-*"]
      cw_dashboards    = ["${local.arn_base}:cloudwatch::${local.account_id}:dashboard/${p}-*"]
      s3_buckets       = ["${local.arn_base}:s3:::${p}-*", "${local.arn_base}:s3:::${p}-*/*"]
      kms_aliases      = [for r in var.allowed_regions : "${local.arn_base}:kms:${r}:${local.account_id}:alias/${p}-*"]
      kms_keys         = [for r in var.allowed_regions : "${local.arn_base}:kms:${r}:${local.account_id}:key/*"]
      ssm_parameters   = [for r in var.allowed_regions : "${local.arn_base}:ssm:${r}:${local.account_id}:parameter/smartcampus/${e}/*"]
      ses              = flatten([for r in var.allowed_regions : ["${local.arn_base}:ses:${r}:${local.account_id}:identity/*", "${local.arn_base}:ses:${r}:${local.account_id}:configuration-set/${p}-*", "${local.arn_base}:ses:${r}:${local.account_id}:template/${p}-*"]])
      acm_certificates = [for r in var.allowed_regions : "${local.arn_base}:acm:${r}:${local.account_id}:certificate/*"]
      wafv2            = flatten([for r in var.allowed_regions : ["${local.arn_base}:wafv2:${r}:${local.account_id}:regional/webacl/${p}-*/*", "${local.arn_base}:wafv2:${r}:${local.account_id}:global/webacl/${p}-*/*", "${local.arn_base}:wafv2:${r}:${local.account_id}:regional/ipset/${p}-*/*", "${local.arn_base}:wafv2:${r}:${local.account_id}:regional/rulegroup/${p}-*/*"]])
      wafv2_managed    = flatten([for r in var.allowed_regions : ["${local.arn_base}:wafv2:${r}::regional/managedruleset/*/*", "${local.arn_base}:wafv2:${r}::global/managedruleset/*/*"]])

      # API Gateway ARNs carry the generated API id. Creation targets the collection ARN (conditioned on the request
      # tag); every other call targets a child ARN, which inherits the tags of its REST API for access control.
      api_gateway_create  = flatten([for r in var.allowed_regions : ["${local.arn_base}:apigateway:${r}::/restapis", "${local.arn_base}:apigateway:${r}::/usageplans"]])
      api_gateway_manage  = flatten([for r in var.allowed_regions : ["${local.arn_base}:apigateway:${r}::/restapis/*", "${local.arn_base}:apigateway:${r}::/usageplans/*"]])
      api_gateway_account = [for r in var.allowed_regions : "${local.arn_base}:apigateway:${r}::/account"]
      api_gateway_tags    = [for r in var.allowed_regions : "${local.arn_base}:apigateway:${r}::/tags/*"]
      cognito_pools       = [for r in var.allowed_regions : "${local.arn_base}:cognito-idp:${r}:${local.account_id}:userpool/*"]

      # Bedrock guardrails and knowledge bases are addressed by a generated ID and carry tags: creation needs the request
      # tag, every other call the resource tag. Models are read-only metadata.
      bedrock_tagged = flatten([for r in var.allowed_regions : ["${local.arn_base}:bedrock:${r}:${local.account_id}:guardrail/*", "${local.arn_base}:bedrock:${r}:${local.account_id}:knowledge-base/*"]])
      bedrock_models = flatten([for r in var.allowed_regions : ["${local.arn_base}:bedrock:${r}::foundation-model/*", "${local.arn_base}:bedrock:${r}:${local.account_id}:inference-profile/*"]])

      # Distributions are tag-controlled. Functions are scoped by name. The other CloudFront resources cannot carry tags
      # and are addressed by a generated ID: both environments may create and read them, only the prod apply role may
      # update or delete them (ADR-0012).
      cloudfront_distributions = ["${local.arn_base}:cloudfront::${local.account_id}:distribution/*"]

      cloudfront_functions = ["${local.arn_base}:cloudfront::${local.account_id}:function/${p}-*"]

      cloudfront_supporting = [
        "${local.arn_base}:cloudfront::${local.account_id}:cache-policy/*",
        "${local.arn_base}:cloudfront::${local.account_id}:origin-access-control/*",
        "${local.arn_base}:cloudfront::${local.account_id}:origin-request-policy/*",
        "${local.arn_base}:cloudfront::${local.account_id}:response-headers-policy/*",
      ]
    }
  }
}

# --- Ceiling of the workload boundaries ---------------------------------------------------------------------------
# A boundary is a ceiling, so its ARNs are scoped by account and name (or tag) and not by region: that keeps the
# document well under the 6144 characters of a managed policy whatever allowed_regions and name_prefix are. The regions
# of the workloads are narrowed by the identity policies of each role.
locals {
  workload_arns = {
    for e, p in local.env_prefix : e => {
      dynamodb_tables = ["${local.arn_base}:dynamodb:*:${local.account_id}:table/${p}-*"]
      events          = ["${local.arn_base}:events:*:${local.account_id}:rule/${p}-*", "${local.arn_base}:events:*:${local.account_id}:event-bus/${p}-*"]
      scheduler       = ["${local.arn_base}:scheduler:*:${local.account_id}:schedule/${p}-*/*", "${local.arn_base}:scheduler:*:${local.account_id}:schedule-group/${p}-*"]
      log_groups      = ["${local.arn_base}:logs:*:${local.account_id}:log-group:/aws/lambda/${p}-*", "${local.arn_base}:logs:*:${local.account_id}:log-group:/aws/apigateway/${p}-*", "${local.arn_base}:logs:*:${local.account_id}:log-group:${p}-*"]
      s3_buckets      = local.env_arns[e].s3_buckets
      sns_topics      = ["${local.arn_base}:sns:*:${local.account_id}:${p}-*"]
      sqs_queues      = ["${local.arn_base}:sqs:*:${local.account_id}:${p}-*"]
      lambda          = ["${local.arn_base}:lambda:*:${local.account_id}:function:${p}-*"]
      kms_keys        = ["${local.arn_base}:kms:*:${local.account_id}:key/*"]
      ssm_parameters  = ["${local.arn_base}:ssm:*:${local.account_id}:parameter/smartcampus/${e}/*"]
      ses             = ["${local.arn_base}:ses:*:${local.account_id}:identity/*", "${local.arn_base}:ses:*:${local.account_id}:configuration-set/${p}-*"]
      bedrock_models  = ["${local.arn_base}:bedrock:*::foundation-model/*", "${local.arn_base}:bedrock:*:${local.account_id}:inference-profile/*"]
      bedrock_runtime = ["${local.arn_base}:bedrock:*:${local.account_id}:guardrail/*", "${local.arn_base}:bedrock:*:${local.account_id}:knowledge-base/*"]
      cognito_pools   = ["${local.arn_base}:cognito-idp:*:${local.account_id}:userpool/*"]
    }
  }
}

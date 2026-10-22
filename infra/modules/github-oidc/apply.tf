# Apply roles (EN-13 AC2, AC3, AC5), one per environment, assumed by jobs bound to the GitHub environment.
#
# Isolation between dev and prod in the single account (ADR-0002, ADR-0012) rests on:
#   - state: read/write only under <env>/* in the shared bucket, explicit Deny on the other environment and bootstrap/;
#   - names: every resource ARN is scoped by <prefix>-<env>-* wherever the service puts the name in the ARN;
#   - IAM: roles must be named <prefix>-<env>-* and carry the workload boundary OF THAT ENVIRONMENT, whose ceiling only
#     covers <prefix>-<env>-* resources (a dev role cannot be given access to prod data, whatever policy is attached);
#   - tags: resources addressed by a generated ID (KMS keys, API Gateway, Cognito, CloudFront distributions, Bedrock
#     guardrails and knowledge bases) are
#     limited to those tagged Environment=<env> and created with that tag; the guardrails deny retagging them across
#     environments.
# CloudFront policies and origin access controls (no tags, no names) are created by both roles but updated and deleted
# by the prod role only.
# Still residual (ADR-0012): reading and creating those CloudFront resources, SES identities, ACM certificates and the
# content of trust policies, which IAM cannot scope.
#
# The policy is split into several managed policies (6144 characters each, 10 attachments per role by default).
#
# Resource "*" is used only for the actions listed in the "NoResourceLevel" statements: they have no resource-level
# support. The unit test en13_ac4_resource_star_only_allowlisted keeps that list closed, and every such Allow carries
# aws:RequestedRegion = var.allowed_regions (unit test en13_ac4_resource_star_allows_region_pinned).

# --- State backend access --------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "apply_state" {
  for_each = local.environments

  statement {
    sid       = "StateObjects"
    effect    = "Allow"
    actions   = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
    resources = ["${var.state_bucket_arn}/${each.key}/*"]
  }

  # IfExists: S3 answers GetObject on a missing key with 404 only when the caller holds s3:ListBucket, and that check
  # carries no s3:prefix key. With a plain StringLike the first init of a new state would fail with 403. Real list
  # requests always carry s3:prefix, so they stay limited to <env>.
  statement {
    sid       = "StateList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.state_bucket_arn]

    condition {
      test     = "StringLikeIfExists"
      variable = "s3:prefix"
      values   = [each.key, "${each.key}/*"]
    }
  }

  statement {
    sid       = "StateKeyUsage"
    effect    = "Allow"
    resources = [var.state_kms_key_arn]

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
  }
}

# --- IAM: roles named <prefix>-<env>-* that carry the workload boundary ---------------------------------------------
# iam:PassRole is limited to sc-<env>-* roles and conditioned on iam:PassedToService.
#trivy:ignore:AVD-AWS-0342
data "aws_iam_policy_document" "apply_iam" {
  for_each = local.environments

  # AC3: a role can only be created, or have its boundary changed, with the workload boundary.
  statement {
    sid       = "RoleCreateWithWorkloadBoundary"
    effect    = "Allow"
    actions   = local.iam_role_create_actions
    resources = ["${local.iam_arn_base}:role/${local.env_prefix[each.key]}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.workload_boundary_arns[each.key]]
    }
  }

  # Attaching or writing policies is only possible on roles that already carry the workload boundary.
  statement {
    sid       = "RolePoliciesWithWorkloadBoundary"
    effect    = "Allow"
    actions   = local.iam_role_policy_actions
    resources = ["${local.iam_arn_base}:role/${local.env_prefix[each.key]}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.workload_boundary_arns[each.key]]
    }
  }

  statement {
    sid       = "RoleManage"
    effect    = "Allow"
    actions   = local.iam_role_manage_actions
    resources = ["${local.iam_arn_base}:role/${local.env_prefix[each.key]}-*"]
  }

  statement {
    sid       = "PolicyManage"
    effect    = "Allow"
    actions   = local.iam_policy_actions
    resources = ["${local.iam_arn_base}:policy/${local.env_prefix[each.key]}-*"]
  }

  statement {
    sid       = "PassRoleToPlatformServices"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["${local.iam_arn_base}:role/${local.env_prefix[each.key]}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = local.passable_services
    }
  }
}

# --- Compute, messaging, observability -------------------------------------------------------------------------------
# Service-level wildcards (lambda:*, dynamodb:* ...) are used only on resources scoped by the environment name prefix:
# the provider calls dozens of actions per resource type and the scope, not the action list, carries the isolation.
#trivy:ignore:AVD-AWS-0057
data "aws_iam_policy_document" "apply_compute" {
  # checkov:skip=CKV_AWS_108: Resource "*" is limited to the NoResourceLevel actions (log group listing, log delivery for WAF, alarm description); no data-plane read.
  # checkov:skip=CKV_AWS_111: Resource "*" is limited to the NoResourceLevel actions, which have no resource-level support.
  # checkov:skip=CKV_AWS_288: Resource "*" is limited to the NoResourceLevel actions, which have no resource-level support.
  # checkov:skip=CKV_AWS_290: Resource "*" is limited to the NoResourceLevel actions, which have no resource-level support.
  # checkov:skip=CKV_AWS_355: Resource "*" is limited to the NoResourceLevel actions, which have no resource-level support.
  # checkov:skip=CKV_AWS_356: Resource "*" is limited to the NoResourceLevel actions, which have no resource-level support.
  for_each = local.environments

  statement {
    sid       = "Lambda"
    effect    = "Allow"
    actions   = ["lambda:*"]
    resources = concat(local.env_arns[each.key].lambda_functions, local.env_arns[each.key].lambda_layers)
  }

  # Event source mappings are addressed by UUID: creation, update and deletion are tied to a function of this
  # environment, so a mapping of the other environment can be neither changed nor deleted.
  statement {
    sid       = "LambdaEventSourceMappingsWrite"
    effect    = "Allow"
    actions   = ["lambda:CreateEventSourceMapping", "lambda:DeleteEventSourceMapping", "lambda:UpdateEventSourceMapping"]
    resources = local.env_arns[each.key].lambda_mappings

    condition {
      test     = "ArnLike"
      variable = "lambda:FunctionArn"
      values   = local.env_arns[each.key].lambda_functions
    }
  }

  statement {
    sid       = "LambdaEventSourceMappingsManage"
    effect    = "Allow"
    resources = local.env_arns[each.key].lambda_mappings

    actions = [
      "lambda:GetEventSourceMapping",
      "lambda:ListTags",
      "lambda:TagResource",
      "lambda:UntagResource",
    ]
  }

  statement {
    sid       = "DynamoDb"
    effect    = "Allow"
    actions   = ["dynamodb:*"]
    resources = local.env_arns[each.key].dynamodb_tables
  }

  statement {
    sid       = "Sqs"
    effect    = "Allow"
    actions   = ["sqs:*"]
    resources = local.env_arns[each.key].sqs_queues
  }

  statement {
    sid       = "Sns"
    effect    = "Allow"
    actions   = ["sns:*"]
    resources = local.env_arns[each.key].sns_topics
  }

  statement {
    sid       = "EventBridge"
    effect    = "Allow"
    actions   = ["events:*"]
    resources = local.env_arns[each.key].event_rules
  }

  statement {
    sid       = "Scheduler"
    effect    = "Allow"
    actions   = ["scheduler:*"]
    resources = local.env_arns[each.key].scheduler
  }

  statement {
    sid       = "LogGroups"
    effect    = "Allow"
    actions   = ["logs:*"]
    resources = local.env_arns[each.key].log_groups
  }

  statement {
    sid       = "CloudWatch"
    effect    = "Allow"
    actions   = ["cloudwatch:*"]
    resources = concat(local.env_arns[each.key].cw_alarms, local.env_arns[each.key].cw_dashboards)
  }

  # No resource-level support: describing log groups and alarms by prefix, and the log delivery / resource policy calls
  # that WAF logging to CloudWatch Logs makes.
  statement {
    sid       = "NoResourceLevel"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "cloudwatch:DescribeAlarms",
      "logs:CreateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:DescribeLogGroups",
      "logs:DescribeResourcePolicies",
      "logs:GetLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:UpdateLogDelivery",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }
}

# --- Storage, keys, parameters ---------------------------------------------------------------------------------------
#trivy:ignore:AVD-AWS-0057
data "aws_iam_policy_document" "apply_data" {
  # checkov:skip=CKV_AWS_111: Resource "*" is limited to the NoResourceLevel actions; kms:CreateKey is conditioned on the Environment request tag.
  # checkov:skip=CKV_AWS_290: Resource "*" is limited to the NoResourceLevel actions; kms:CreateKey is conditioned on the Environment request tag.
  # checkov:skip=CKV_AWS_355: Resource "*" is limited to the NoResourceLevel actions, which have no resource-level support.
  # checkov:skip=CKV_AWS_356: Resource "*" is limited to the NoResourceLevel actions, which have no resource-level support.
  for_each = local.environments

  statement {
    sid       = "Buckets"
    effect    = "Allow"
    resources = local.env_arns[each.key].s3_buckets

    # Bucket configuration managed by OpenTofu; object writes cover SPA and Lambda artifacts.
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:Get*",
      "s3:List*",
      "s3:PutAccelerateConfiguration",
      "s3:PutBucketAcl",
      "s3:PutBucketCORS",
      "s3:PutBucketLogging",
      "s3:PutBucketNotification",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
      "s3:PutBucketWebsite",
      "s3:PutEncryptionConfiguration",
      "s3:PutIntelligentTieringConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:PutReplicationConfiguration",
    ]
  }

  statement {
    sid       = "Parameters"
    effect    = "Allow"
    resources = local.env_arns[each.key].ssm_parameters

    actions = [
      "ssm:AddTagsToResource",
      "ssm:DeleteParameter",
      "ssm:DeleteParameters",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:ListTagsForResource",
      "ssm:PutParameter",
      "ssm:RemoveTagsFromResource",
    ]
  }

  # Keys are addressed by ID: creation requires the Environment request tag, later calls require the Environment
  # resource tag. The state key carries Environment=shared, so it is out of reach whatever the explicit Denies say.
  statement {
    sid       = "KeyCreate"
    effect    = "Allow"
    actions   = ["kms:CreateKey"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }

  # KMS requires kms:TagResource in an IAM policy to create a key WITH tags (the provider always sends the default
  # tags), and the permission has to cover all keys of the account. It stays a separate statement so that the price of
  # that requirement is explicit: this Allow can retag a key, so the guardrails deny kms:TagResource and
  # kms:UntagResource on any key that already carries the Environment tag of another environment, and any change of
  # the Environment tag itself on a key that already carries it (apply_guardrails: DenyForeignEnvironmentTagging,
  # DenyEnvironmentTagChange). Only a key without Environment tag can be claimed: platform keys always carry it
  # (provider default_tags).
  statement {
    sid       = "KeyTagOnCreate"
    effect    = "Allow"
    actions   = ["kms:TagResource"]
    resources = local.env_arns[each.key].kms_keys

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "KeyManage"
    effect    = "Allow"
    resources = local.env_arns[each.key].kms_keys

    actions = [
      "kms:CancelKeyDeletion",
      "kms:CreateAlias",
      "kms:CreateGrant",
      "kms:DeleteAlias",
      "kms:DescribeKey",
      "kms:DisableKey",
      "kms:DisableKeyRotation",
      "kms:EnableKey",
      "kms:EnableKeyRotation",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListGrants",
      "kms:ListResourceTags",
      "kms:PutKeyPolicy",
      "kms:RevokeGrant",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateAlias",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "KeyAliases"
    effect    = "Allow"
    actions   = ["kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias"]
    resources = local.env_arns[each.key].kms_aliases
  }

  statement {
    sid       = "NoResourceLevel"
    effect    = "Allow"
    actions   = ["kms:ListAliases", "ssm:DescribeParameters"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }
}

# --- API, identity, AI, mail -----------------------------------------------------------------------------------------
# ID-addressed resources are limited to the account, the allowed regions and the Environment tag (ADR-0012).
#trivy:ignore:AVD-AWS-0057
data "aws_iam_policy_document" "apply_edge" {
  # checkov:skip=CKV_AWS_111: Resource "*" is limited to cognito-idp:CreateUserPool and the bedrock Create actions (no resource-level support), conditioned on the Environment request tag.
  # checkov:skip=CKV_AWS_290: Resource "*" is limited to cognito-idp:CreateUserPool and the bedrock Create actions (no resource-level support), conditioned on the Environment request tag.
  # checkov:skip=CKV_AWS_355: Resource "*" is limited to cognito-idp:CreateUserPool and the bedrock Create actions (no resource-level support), conditioned on the Environment request tag.
  # checkov:skip=CKV_AWS_356: Resource "*" is limited to cognito-idp:CreateUserPool and the bedrock Create actions (no resource-level support), conditioned on the Environment request tag.
  for_each = local.environments

  # API Gateway (F4): creation needs the Environment request tag; every other call on an API or usage plan needs the
  # Environment tag of the REST API (child resources inherit it for access control). The authorizer, the methods and
  # the stages of an API of the other environment are therefore out of reach.
  statement {
    sid       = "ApiGatewayCreate"
    effect    = "Allow"
    actions   = ["apigateway:POST"]
    resources = local.env_arns[each.key].api_gateway_create

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid     = "ApiGatewayManage"
    effect  = "Allow"
    actions = ["apigateway:DELETE", "apigateway:GET", "apigateway:PATCH", "apigateway:POST", "apigateway:PUT", "apigateway:SetWebACL", "apigateway:UpdateRestApiPolicy"]

    resources = local.env_arns[each.key].api_gateway_manage

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  # The CloudWatch role of API Gateway is a singleton of the region, shared by both environments (residual, ADR-0012).
  statement {
    sid       = "ApiGatewayAccount"
    effect    = "Allow"
    actions   = ["apigateway:GET", "apigateway:PATCH"]
    resources = local.env_arns[each.key].api_gateway_account
  }

  # Tags of an API are changed through /tags/<arn>. Changing the Environment tag is denied in apply_guardrails.
  statement {
    sid       = "ApiGatewayTags"
    effect    = "Allow"
    actions   = ["apigateway:DELETE", "apigateway:GET", "apigateway:PUT"]
    resources = local.env_arns[each.key].api_gateway_tags
  }

  # Cognito (F4): pool, client, group and provider administration on pools tagged with the environment. The user data
  # plane is denied in apply_guardrails. CreateUserPool has no resource-level support: it needs Resource "*" with the
  # Environment request tag (CognitoCreate); TagResource is limited to pool ARNs.
  statement {
    sid       = "CognitoCreate"
    effect    = "Allow"
    actions   = ["cognito-idp:CreateUserPool"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }

  statement {
    sid       = "CognitoTagOnCreate"
    effect    = "Allow"
    actions   = ["cognito-idp:TagResource"]
    resources = local.env_arns[each.key].cognito_pools

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "CognitoManage"
    effect    = "Allow"
    actions   = ["cognito-idp:*"]
    resources = local.env_arns[each.key].cognito_pools

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "Ses"
    effect    = "Allow"
    actions   = ["ses:*"]
    resources = local.env_arns[each.key].ses
  }

  # Bedrock (F4): guardrails and knowledge bases follow the tag rule. CreateGuardrail and CreateKnowledgeBase have no
  # resource-level support: Resource "*" with the Environment request tag. TagResource is limited to their ARNs, and the
  # guardrails deny retagging across environments. The runtime (InvokeModel, Retrieve, ApplyGuardrail) is not granted
  # to the apply roles.
  statement {
    sid       = "BedrockCreate"
    effect    = "Allow"
    actions   = ["bedrock:CreateGuardrail", "bedrock:CreateKnowledgeBase"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }

  statement {
    sid       = "BedrockTagOnCreate"
    effect    = "Allow"
    actions   = ["bedrock:TagResource"]
    resources = local.env_arns[each.key].bedrock_tagged

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "BedrockManage"
    effect    = "Allow"
    resources = local.env_arns[each.key].bedrock_tagged

    actions = [
      "bedrock:CreateDataSource",
      "bedrock:CreateGuardrailVersion",
      "bedrock:DeleteDataSource",
      "bedrock:DeleteGuardrail",
      "bedrock:DeleteKnowledgeBase",
      "bedrock:GetDataSource",
      "bedrock:GetGuardrail",
      "bedrock:GetIngestionJob",
      "bedrock:GetKnowledgeBase",
      "bedrock:ListDataSources",
      "bedrock:ListIngestionJobs",
      "bedrock:ListTagsForResource",
      "bedrock:StartIngestionJob",
      "bedrock:TagResource",
      "bedrock:UntagResource",
      "bedrock:UpdateDataSource",
      "bedrock:UpdateGuardrail",
      "bedrock:UpdateKnowledgeBase",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "BedrockModelsRead"
    effect    = "Allow"
    actions   = ["bedrock:GetFoundationModel", "bedrock:GetInferenceProfile"]
    resources = local.env_arns[each.key].bedrock_models
  }

  statement {
    sid       = "Acm"
    effect    = "Allow"
    actions   = ["acm:*"]
    resources = local.env_arns[each.key].acm_certificates
  }
}

# --- Web ACLs and CDN (F4) ---------------------------------------------------------------------------------------------
# A separate policy: the ARN lists are repeated for each region and the 6144 characters of a managed policy are close
# when the edge policy carries them all.
#trivy:ignore:AVD-AWS-0057
data "aws_iam_policy_document" "apply_cdn" {
  for_each = local.environments

  # WAF (F4): web ACLs, IP sets and rule groups are named <prefix>-<env>-*; on top of the name, creation needs the
  # request tag and every other call the resource tag.
  statement {
    sid       = "Wafv2Create"
    effect    = "Allow"
    actions   = ["wafv2:CreateIPSet", "wafv2:CreateRuleGroup", "wafv2:CreateWebACL", "wafv2:TagResource"]
    resources = local.env_arns[each.key].wafv2

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "Wafv2Manage"
    effect    = "Allow"
    actions   = ["wafv2:*"]
    resources = local.env_arns[each.key].wafv2

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "Wafv2ManagedRuleGroups"
    effect    = "Allow"
    actions   = ["wafv2:DescribeManagedRuleGroup", "wafv2:GetManagedRuleSet"]
    resources = local.env_arns[each.key].wafv2_managed
  }

  # CloudFront (F4): distributions follow the same tag rule (create with the request tag, manage with the resource
  # tag). Functions are scoped by name. Cache, origin request and response headers policies and origin access controls
  # cannot carry tags and are not name-scoped: both roles may create and read them, but only the prod apply role may
  # update, delete or publish them, so dev cannot alter the shared or prod ones (ADR-0012).
  statement {
    sid       = "CloudFrontDistributionCreate"
    effect    = "Allow"
    actions   = ["cloudfront:CreateDistribution", "cloudfront:CreateDistributionWithTags", "cloudfront:TagResource"]
    resources = local.env_arns[each.key].cloudfront_distributions

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "CloudFrontDistributionManage"
    effect    = "Allow"
    actions   = ["cloudfront:*"]
    resources = local.env_arns[each.key].cloudfront_distributions

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "CloudFrontFunctions"
    effect    = "Allow"
    actions   = ["cloudfront:*"]
    resources = local.env_arns[each.key].cloudfront_functions
  }

  statement {
    sid       = "CloudFrontSupportingRead"
    effect    = "Allow"
    actions   = ["cloudfront:Create*", "cloudfront:Describe*", "cloudfront:Get*", "cloudfront:List*"]
    resources = local.env_arns[each.key].cloudfront_supporting
  }

  dynamic "statement" {
    for_each = each.key == "prod" ? [1] : []

    content {
      sid       = "CloudFrontSupportingWrite"
      effect    = "Allow"
      actions   = ["cloudfront:Delete*", "cloudfront:Publish*", "cloudfront:Update*"]
      resources = local.env_arns[each.key].cloudfront_supporting
    }
  }
}

# --- Explicit Denies (AC3, AC5, ADR-0011) ----------------------------------------------------------------------------
data "aws_iam_policy_document" "apply_guardrails" {
  for_each = local.environments

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

  # A missing iam:PermissionsBoundary key also matches StringNotEquals, so CreateRole without a boundary is refused.
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

  statement {
    sid       = "DenyLongLivedCredentials"
    effect    = "Deny"
    actions   = local.credential_actions
    resources = local.any_user_arns
  }

  statement {
    sid       = "DenyStateKeyDestruction"
    effect    = "Deny"
    resources = [var.state_kms_key_arn]

    actions = [
      "kms:CreateGrant",
      "kms:DisableKey",
      "kms:DisableKeyRotation",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
    ]
  }

  # F2/F4: a resource addressed by a generated ID belongs to the environment of its Environment tag. A tag of another
  # environment (or "shared" for the state key) cannot be rewritten by this role, which closes the retag-then-manage
  # path. A resource that has no Environment tag yet can still be tagged, which is what creation with tags needs.
  statement {
    sid       = "DenyForeignEnvironmentTagging"
    effect    = "Deny"
    actions   = local.tag_guarded_actions
    resources = ["*"]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/Environment"
      values   = ["false"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  # Even inside its own environment the Environment tag is frozen once set.
  statement {
    sid       = "DenyEnvironmentTagChange"
    effect    = "Deny"
    actions   = local.tag_guarded_actions
    resources = ["*"]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/Environment"
      values   = ["false"]
    }

    condition {
      test     = "ForAnyValue:StringEqualsIgnoreCase"
      variable = "aws:TagKeys"
      values   = ["Environment"]
    }
  }

  # API Gateway tags go through /tags/<arn> and cannot be tested on the resource tag there: the Environment key is
  # never written through that path (creation sends it in the create request).
  statement {
    sid       = "DenyApiGatewayEnvironmentTagChange"
    effect    = "Deny"
    actions   = ["apigateway:DELETE", "apigateway:PATCH", "apigateway:POST", "apigateway:PUT"]
    resources = local.env_arns[each.key].api_gateway_tags

    condition {
      test     = "ForAnyValue:StringEqualsIgnoreCase"
      variable = "aws:TagKeys"
      values   = ["Environment"]
    }
  }

  # F4: pools, clients and groups are administered, the users inside them never.
  statement {
    sid       = "DenyCognitoUserDataPlane"
    effect    = "Deny"
    actions   = local.cognito_user_data_actions
    resources = ["*"]
  }

  statement {
    sid       = "DenyStateBucketTampering"
    effect    = "Deny"
    resources = [var.state_bucket_arn]

    actions = [
      "s3:DeleteBucket*",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
    ]
  }

  statement {
    sid       = "DenyStateVersionDeletion"
    effect    = "Deny"
    actions   = ["s3:DeleteObjectVersion"]
    resources = [local.state_objects_arn]
  }

  # ADR-0011: the state key does not separate environments, this Deny does. bootstrap/ holds the CI roles themselves.
  statement {
    sid     = "DenyOtherEnvAndBootstrapStateWrite"
    effect  = "Deny"
    actions = ["s3:AbortMultipartUpload", "s3:DeleteObject", "s3:PutObject", "s3:PutObjectTagging"]

    resources = [
      "${var.state_bucket_arn}/${local.other_environment[each.key]}/*",
      "${var.state_bucket_arn}/bootstrap/*",
    ]
  }
}

locals {
  apply_policy_documents = {
    for e in local.environments : e => {
      state      = data.aws_iam_policy_document.apply_state[e].json
      iam        = data.aws_iam_policy_document.apply_iam[e].json
      compute    = data.aws_iam_policy_document.apply_compute[e].json
      data       = data.aws_iam_policy_document.apply_data[e].json
      edge       = data.aws_iam_policy_document.apply_edge[e].json
      cdn        = data.aws_iam_policy_document.apply_cdn[e].json
      guardrails = data.aws_iam_policy_document.apply_guardrails[e].json
    }
  }

  apply_policies = merge([
    for e, documents in local.apply_policy_documents : {
      for key, json in documents : "${e}-${key}" => { env = e, key = key, json = json }
    }
  ]...)
}

resource "aws_iam_role" "apply" {
  for_each = local.environments

  name                 = local.apply_role_names[each.key]
  description          = "GitHub Actions apply role for ${each.key}: assumed by jobs of the ${each.key} GitHub environment (EN-13)."
  assume_role_policy   = data.aws_iam_policy_document.trust_apply[each.key].json
  max_session_duration = local.max_session_duration
  permissions_boundary = local.ci_boundary_arn

  tags = merge(var.tags, { Name = local.apply_role_names[each.key], Environment = each.key })

  depends_on = [aws_iam_policy.ci_boundary]
}

resource "aws_iam_policy" "apply" {
  for_each = local.apply_policies

  name        = "${local.apply_role_names[each.value.env]}-${each.value.key}"
  description = "Apply role policy (${each.value.key}) for the ${each.value.env} environment (EN-13)."
  policy      = each.value.json

  tags = merge(var.tags, { Environment = each.value.env })
}

resource "aws_iam_role_policy_attachment" "apply" {
  for_each = local.apply_policies

  role       = aws_iam_role.apply[each.value.env].name
  policy_arn = aws_iam_policy.apply[each.key].arn
}

# Plan role (EN-13 AC1): read-only, assumed by pull_request workflows.
#
# Identity policies of the role:
#   1. AWS managed ReadOnlyAccess. Justification: `tofu plan` refreshes every resource of every stack and needs the
#      Describe/Get/List actions of all the services the platform uses; listing them by hand would be incomplete
#      for the services not deployed yet and would break each new stack. The breadth is compensated by the explicit
#      Deny of plan_deny below (data-plane reads) and by the ci-boundary ceiling. Residual risk: ADR-0012.
#   2. plan_state: read of the DEV state only, no S3 write at all, state key usage.
#   3. plan_deny: data-plane reads of secrets and personal data are denied whatever ReadOnlyAccess grants.
#
# Any branch can assume this role (ADR-0012, risk 2), so it only reaches what a pull request may see:
#   - the state under dev/*: prod and bootstrap/ states (the latter holds secrets such as the Entra client_secret) are
#     out of reach; prod plans are computed inside the prod apply job, behind the environment approval;
#   - no S3 write: PR plans run with -lock=false, so a pull request can neither create nor delete a lock file (deleting
#     a prod lock during an apply could corrupt the state) nor alter a state file.

data "aws_iam_policy_document" "plan_state" {
  statement {
    sid       = "StateRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [local.plan_state_objects_arn]
  }

  # IfExists: S3 answers GetObject on a missing key with 404 only when the caller holds s3:ListBucket, and that check
  # carries no s3:prefix key (same reasoning as the apply roles). Real list requests always carry s3:prefix, so they
  # stay limited to dev.
  statement {
    sid       = "StateList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.state_bucket_arn]

    condition {
      test     = "StringLikeIfExists"
      variable = "s3:prefix"
      values   = [local.plan_state_environment, "${local.plan_state_environment}/*"]
    }
  }

  # Decrypt reads the encrypted state; Encrypt / GenerateDataKey: client-side plan encryption of the OpenTofu
  # encryption block (these are KMS calls, not S3 writes).
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

data "aws_iam_policy_document" "plan_deny" {
  statement {
    sid       = "DenyDataPlaneReads"
    effect    = "Deny"
    resources = ["*"]

    actions = [
      "cognito-idp:AdminGetUser",
      "cognito-idp:ListUsers",
      "cognito-idp:ListUsersInGroup",
      "athena:GetQueryResults",
      "dynamodb:BatchGetItem",
      "dynamodb:GetItem",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:PartiQLSelect",
      "dynamodb:Query",
      "dynamodb:Scan",
      "kinesis:GetRecords",
      "logs:FilterLogEvents",
      "logs:GetLogEvents",
      "logs:GetLogRecord",
      "logs:GetQueryResults",
      "logs:StartLiveTail",
      "logs:StartQuery",
      "secretsmanager:GetSecretValue",
      "sqs:ReceiveMessage",
    ]
  }

  # SecureString parameters are protected by this Deny: IAM has no condition key for the parameter type, and reading a
  # SecureString with decryption needs kms:Decrypt on its key. Plain String parameters (the cross-stack contract under
  # /smartcampus/<env>/) stay readable, the plan needs them.
  statement {
    sid           = "DenyDecryptExceptStateKey"
    effect        = "Deny"
    actions       = ["kms:Decrypt"]
    not_resources = [var.state_kms_key_arn]
  }

  statement {
    sid           = "DenyObjectReadsExceptState"
    effect        = "Deny"
    actions       = ["s3:GetObject", "s3:GetObjectVersion"]
    not_resources = [local.plan_state_objects_arn]
  }
}

resource "aws_iam_role" "plan" {
  name                 = local.plan_role_name
  description          = "GitHub Actions plan role: read-only, assumed by pull_request workflows (EN-13)."
  assume_role_policy   = data.aws_iam_policy_document.trust_plan.json
  max_session_duration = local.max_session_duration
  permissions_boundary = local.ci_boundary_arn

  tags = merge(var.tags, { Name = local.plan_role_name })

  # The boundary must exist before the role references it.
  depends_on = [aws_iam_policy.ci_boundary]
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = "${local.arn_base}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "state"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_state.json
}

resource "aws_iam_role_policy" "plan_deny" {
  name   = "deny-data-plane-reads"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_deny.json
}

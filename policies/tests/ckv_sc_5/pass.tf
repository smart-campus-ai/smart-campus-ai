# tflint-ignore-file: terraform_unused_declarations, terraform_required_providers, terraform_required_version, terraform_standard_module_structure
# Fixture of CKV_SC_5: documents named pass_* must PASS.

variable "oidc_sub" {
  type = string
}

data "aws_iam_policy_document" "pass_github_oidc_pinned" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:smart-campus-ai/smart-campus-ai:pull_request"]
    }
  }
}

# The subject is an unresolved variable: accepted because the test is StringEquals (documented limit).
data "aws_iam_policy_document" "pass_github_oidc_unresolved_sub" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [var.oidc_sub]
    }
  }
}

data "aws_iam_policy_document" "pass_lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

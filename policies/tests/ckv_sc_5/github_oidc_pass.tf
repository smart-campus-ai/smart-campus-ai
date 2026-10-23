# tflint-ignore-file: terraform_unused_declarations, terraform_required_providers, terraform_required_version, terraform_standard_module_structure
# Fixture of CKV_SC_5: documents named pass_* must PASS.

locals {
  oidc_host         = "token.actions.githubusercontent.com"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  oidc_audience     = "sts.amazonaws.com"
}

# GitHub OIDC principal with literal conditions (apply role)
data "aws_iam_policy_document" "pass_github_oidc_apply" {
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
      values   = ["repo:smart-campus-ai/smart-campus-ai:environment:apply"]
    }
  }
}

# GitHub OIDC principal with literal conditions (read-only plan role)
data "aws_iam_policy_document" "pass_github_oidc_plan" {
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

# Interpolated form, as written in infra/modules/github-oidc/trust.tf: Checkov does not resolve the locals.
data "aws_iam_policy_document" "pass_github_oidc_interpolated" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = [local.oidc_audience]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["repo:smart-campus-ai/smart-campus-ai:pull_request"]
    }
  }
}

# Mixed: Service principal + GitHub OIDC (both allowed)
data "aws_iam_policy_document" "pass_mixed" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }

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
      values   = ["repo:smart-campus-ai/smart-campus-ai:environment:apply"]
    }
  }
}

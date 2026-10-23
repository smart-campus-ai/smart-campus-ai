# tflint-ignore-file: terraform_unused_declarations, terraform_required_providers, terraform_required_version, terraform_standard_module_structure
# Fixture of CKV_SC_5: documents named fail_* must FAIL.

data "aws_iam_policy_document" "fail_aws_principal" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::123456789012:root"]
    }
  }
}

data "aws_iam_policy_document" "fail_federated_principal" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"]
    }
  }
}

# Federated with only an ':aud' condition: the subject is not pinned.
data "aws_iam_policy_document" "fail_federated_without_sub" {
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
  }
}

# Federated with StringLike on the subject: wildcards are not allowed.
data "aws_iam_policy_document" "fail_federated_stringlike" {
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
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:org/*"]
    }
  }
}

# Wildcard in the subject, even under StringEquals.
data "aws_iam_policy_document" "fail_federated_wildcard_sub" {
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
      values   = ["repo:*"]
    }
  }
}

# Subject of another repository.
data "aws_iam_policy_document" "fail_federated_other_repo" {
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
      values   = ["repo:attacker/other-repo:pull_request"]
    }
  }
}

# Wrong audience.
data "aws_iam_policy_document" "fail_federated_wrong_audience" {
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
      values   = ["attacker.example.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:smart-campus-ai/smart-campus-ai:pull_request"]
    }
  }
}

# Correct conditions, but the federated provider is not GitHub.
data "aws_iam_policy_document" "fail_federated_other_provider" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::123456789012:oidc-provider/oidc.attacker.example.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "oidc.attacker.example.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "oidc.attacker.example.com:sub"
      values   = ["repo:smart-campus-ai/smart-campus-ai:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "fail_service_and_wildcard" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

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

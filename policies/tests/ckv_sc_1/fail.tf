# Fixture of CKV_SC_1: resources named fail_* must FAIL.

resource "aws_iam_role" "fail_aws_principal" {
  name                 = "fixture-fail-aws"
  permissions_boundary = "arn:aws:iam::123456789012:policy/fixture-boundary"

  assume_role_policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "sts:AssumeRole",
          "Principal": { "AWS": "arn:aws:iam::123456789012:root" }
        }
      ]
    }
  EOT
}

resource "aws_iam_role" "fail_federated_principal" {
  name                 = "fixture-fail-federated"
  permissions_boundary = "arn:aws:iam::123456789012:policy/fixture-boundary"

  assume_role_policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Principal": { "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
        }
      ]
    }
  EOT
}

resource "aws_iam_role" "fail_mixed_principals" {
  name                 = "fixture-fail-mixed"
  permissions_boundary = "arn:aws:iam::123456789012:policy/fixture-boundary"

  assume_role_policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "sts:AssumeRole",
          "Principal": { "Service": "lambda.amazonaws.com", "AWS": "*" }
        }
      ]
    }
  EOT
}

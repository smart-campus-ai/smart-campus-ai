# tflint-ignore-file: terraform_unused_declarations, terraform_required_providers, terraform_required_version, terraform_standard_module_structure
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

# GitHub OIDC trust: StringLike on the subject accepts wildcards.
resource "aws_iam_role" "fail_oidc_stringlike" {
  name                 = "fixture-fail-oidc-stringlike"
  permissions_boundary = "arn:aws:iam::123456789012:policy/fixture-boundary"

  assume_role_policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Principal": { "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" },
          "Condition": {
            "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
            "StringLike": { "token.actions.githubusercontent.com:sub": "repo:smart-campus-ai/smart-campus-ai:*" }
          }
        }
      ]
    }
  EOT
}

# GitHub OIDC trust: wildcard in the subject, even under StringEquals.
resource "aws_iam_role" "fail_oidc_wildcard_sub" {
  name                 = "fixture-fail-oidc-wildcard"
  permissions_boundary = "arn:aws:iam::123456789012:policy/fixture-boundary"

  assume_role_policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Principal": { "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" },
          "Condition": {
            "StringEquals": {
              "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
              "token.actions.githubusercontent.com:sub": "repo:*"
            }
          }
        }
      ]
    }
  EOT
}

# GitHub OIDC trust: any repository of another organisation.
resource "aws_iam_role" "fail_oidc_other_repo" {
  name                 = "fixture-fail-oidc-other-repo"
  permissions_boundary = "arn:aws:iam::123456789012:policy/fixture-boundary"

  assume_role_policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Principal": { "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" },
          "Condition": {
            "StringEquals": {
              "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
              "token.actions.githubusercontent.com:sub": "repo:attacker/other-repo:pull_request"
            }
          }
        }
      ]
    }
  EOT
}

# GitHub OIDC trust: wrong audience.
resource "aws_iam_role" "fail_oidc_wrong_audience" {
  name                 = "fixture-fail-oidc-audience"
  permissions_boundary = "arn:aws:iam::123456789012:policy/fixture-boundary"

  assume_role_policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Principal": { "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" },
          "Condition": {
            "StringEquals": {
              "token.actions.githubusercontent.com:aud": "attacker.example.com",
              "token.actions.githubusercontent.com:sub": "repo:smart-campus-ai/smart-campus-ai:pull_request"
            }
          }
        }
      ]
    }
  EOT
}

# Correct conditions, but the federated provider is not GitHub.
resource "aws_iam_role" "fail_oidc_other_provider" {
  name                 = "fixture-fail-oidc-provider"
  permissions_boundary = "arn:aws:iam::123456789012:policy/fixture-boundary"

  assume_role_policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Principal": { "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.attacker.example.com" },
          "Condition": {
            "StringEquals": {
              "oidc.attacker.example.com:aud": "sts.amazonaws.com",
              "oidc.attacker.example.com:sub": "repo:smart-campus-ai/smart-campus-ai:pull_request"
            }
          }
        }
      ]
    }
  EOT
}

# tflint-ignore-file: terraform_unused_declarations, terraform_required_providers, terraform_required_version, terraform_standard_module_structure
# Fixture of CKV_SC_1: resources named pass_* must PASS.

# GitHub OIDC principal with proper conditions (apply role)
resource "aws_iam_role" "pass_github_oidc_apply" {
  name                 = "fixture-pass-github-oidc-apply"
  permissions_boundary = "arn:aws:iam::123456789012:policy/fixture-boundary"

  assume_role_policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Principal": {
            "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
          },
          "Condition": {
            "StringEquals": {
              "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
              "token.actions.githubusercontent.com:sub": "repo:smart-campus-ai/smart-campus-ai:environment:apply"
            }
          }
        }
      ]
    }
  EOT
}

# GitHub OIDC principal with proper conditions (read-only plan role)
resource "aws_iam_role" "pass_github_oidc_plan" {
  name                 = "fixture-pass-github-oidc-plan"
  permissions_boundary = "arn:aws:iam::123456789012:policy/fixture-boundary"

  assume_role_policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Principal": {
            "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
          },
          "Condition": {
            "StringEquals": {
              "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
              "token.actions.githubusercontent.com:sub": "repo:smart-campus-ai/smart-campus-ai:pull_request"
            }
          }
        }
      ]
    }
  EOT
}

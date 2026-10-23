# tflint-ignore-file: terraform_unused_declarations, terraform_required_providers, terraform_required_version, terraform_standard_module_structure
# Fixture of CKV_SC_3: resources named fail_* must FAIL.

resource "aws_iam_role" "fail_without_boundary" {
  name = "fixture-fail-boundary"

  assume_role_policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "sts:AssumeRole",
          "Principal": { "Service": "lambda.amazonaws.com" }
        }
      ]
    }
  EOT
}

resource "aws_iam_role" "fail_empty_boundary" {
  name = "fixture-fail-empty-boundary"

  assume_role_policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "sts:AssumeRole",
          "Principal": { "Service": "lambda.amazonaws.com" }
        }
      ]
    }
  EOT
}

# Fixture of CKV_SC_3: resources named pass_* must PASS.

resource "aws_iam_role" "pass_with_boundary" {
  name                 = "fixture-pass-boundary"
  permissions_boundary = "arn:aws:iam::123456789012:policy/fixture-boundary"

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

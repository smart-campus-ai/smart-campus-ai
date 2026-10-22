# Fixture of CKV_SC_5: documents named pass_* must PASS.

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

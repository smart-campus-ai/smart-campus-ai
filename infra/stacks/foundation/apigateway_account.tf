# API Gateway account settings: the CloudWatch Logs role. The setting is unique per account and region, and API Gateway
# refuses to create a stage with access logs or execution logs until it is set. Dev and prod share the workshop account
# (ADR-0002), so only one environment manages it (manage_api_gateway_account: true in dev, false in prod).
#
# No permissions boundary: the workshop account cannot attach one (ADR-0014, option B). The role only trusts API
# Gateway for this account and carries the AWS managed push-to-CloudWatch-Logs policy, which has no other permission.
data "aws_iam_policy_document" "apigw_cloudwatch_trust" {
  statement {
    sid     = "ApiGatewayAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }

    # Confused deputy: only API Gateway acting for this account.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "apigw_cloudwatch" {
  count = var.manage_api_gateway_account ? 1 : 0

  name                 = "${var.name_prefix}-apigw-cloudwatch"
  description          = "Lets API Gateway push logs to CloudWatch Logs (account setting shared by the environments)."
  assume_role_policy   = data.aws_iam_policy_document.apigw_cloudwatch_trust.json
  permissions_boundary = null

  tags = {
    Name = "${var.name_prefix}-apigw-cloudwatch"
  }
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  count = var.manage_api_gateway_account ? 1 : 0

  role       = aws_iam_role.apigw_cloudwatch[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  count = var.manage_api_gateway_account ? 1 : 0

  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch[0].arn

  # The role must hold its policy before API Gateway validates it.
  depends_on = [aws_iam_role_policy_attachment.apigw_cloudwatch]
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  name           = "${var.name_prefix}-${var.function_name}"
  role_name      = "${local.name}-role"
  dlq_name       = "${local.name}-dlq"
  log_group_name = "/aws/lambda/${local.name}"
  alias_name     = "live"

  # Built from the name, not from the function resource: the role trust policy is needed to create the function.
  function_arn = "arn:${local.partition}:lambda:${local.region}:${local.account_id}:function:${local.name}"

  tags = merge(var.tags, { Name = local.name })

  # Send action the execution role needs on the on-failure destination, derived from the service in the ARN.
  destination_actions = {
    sqs    = ["sqs:SendMessage"]
    sns    = ["sns:Publish"]
    events = ["events:PutEvents"]
    lambda = ["lambda:InvokeFunction"]
  }
  destination_service = var.on_failure_destination_arn == null ? null : split(":", var.on_failure_destination_arn)[2]
}

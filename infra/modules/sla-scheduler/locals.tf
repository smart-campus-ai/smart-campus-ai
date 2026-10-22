data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  group_name = "${var.name_prefix}-sla"
  role_name  = "${var.name_prefix}-sla-scheduler"
  dlq_name   = "${var.name_prefix}-sla-dlq"

  # Built from names rather than from resource attributes: the trust policy of the role is needed to create the role,
  # and the group does not depend on the role.
  scheduler_arn_prefix = "arn:${local.partition}:scheduler:${local.region}:${local.account_id}"
  group_arn            = "${local.scheduler_arn_prefix}:schedule-group/${local.group_name}"
  schedules_arn        = "${local.scheduler_arn_prefix}:schedule/${local.group_name}/*"
}

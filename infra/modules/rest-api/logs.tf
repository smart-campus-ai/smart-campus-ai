resource "aws_cloudwatch_log_group" "access" {
  # checkov:skip=CKV_AWS_338: Retention follows the environment policy (dev 14 days, prod 90 days) and is set through log_retention_days.
  name              = local.access_log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = local.access_log_group_name })
}

# Execution logs (level ERROR). API Gateway writes to this exact name; creating it first keeps it encrypted and bounded.
resource "aws_cloudwatch_log_group" "execution" {
  # checkov:skip=CKV_AWS_338: Retention follows the environment policy (dev 14 days, prod 90 days) and is set through log_retention_days.
  name              = local.execution_log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = "${local.name}-${var.stage_name}-execution" })
}

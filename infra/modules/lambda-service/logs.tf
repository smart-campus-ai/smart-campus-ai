resource "aws_cloudwatch_log_group" "this" {
  # checkov:skip=CKV_AWS_338: Retention is set per environment (dev 14 days, prod 90 days, iac steering) to limit the personal data kept in logs; one year is not required.
  name              = local.log_group_name
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.logs_kms_key_arn

  tags = local.tags
}

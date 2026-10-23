# tflint-ignore-file: terraform_unused_declarations, terraform_required_providers, terraform_required_version, terraform_standard_module_structure
# Fixture of CKV_SC_4: resources named fail_* must FAIL.

resource "aws_cloudwatch_log_group" "fail_no_kms" {
  name              = "/fixture/fail-no-kms"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "fail_no_retention" {
  name       = "/fixture/fail-no-retention"
  kms_key_id = "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000"
}

resource "aws_cloudwatch_log_group" "fail_never_expires" {
  name              = "/fixture/fail-never-expires"
  kms_key_id        = "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000"
  retention_in_days = 0
}

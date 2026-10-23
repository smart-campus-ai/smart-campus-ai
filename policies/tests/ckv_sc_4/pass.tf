# tflint-ignore-file: terraform_unused_declarations, terraform_required_providers, terraform_required_version, terraform_standard_module_structure
# Fixture of CKV_SC_4: resources named pass_* must PASS.

resource "aws_cloudwatch_log_group" "pass_kms_and_retention" {
  name              = "/fixture/pass"
  kms_key_id        = "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000"
  retention_in_days = 14
}

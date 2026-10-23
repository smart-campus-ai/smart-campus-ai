# tflint-ignore-file: terraform_unused_declarations, terraform_required_providers, terraform_required_version, terraform_standard_module_structure
# Fixture of CKV_SC_2: resource reached through module "state_backend" (see ../pass.tf), expected to PASS by exclusion.

resource "aws_kms_key" "pass_shared_state_backend" {
  description         = "fixture"
  enable_key_rotation = true

  tags = {
    Name = "state-backend-key"
  }
}

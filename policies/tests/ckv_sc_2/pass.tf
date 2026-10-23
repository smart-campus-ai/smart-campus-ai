# tflint-ignore-file: terraform_unused_declarations, terraform_required_providers, terraform_required_version, terraform_standard_module_structure
# Fixture of CKV_SC_2: resources named pass_* must PASS.

# The state backend key is shared by dev and prod (ADR-0011) and has no Environment tag. It is excluded by its address
# (module.state_backend.*), not by a Checkov skip: the key lives in ./state_backend/main.tf.
module "state_backend" {
  source = "./state_backend"
}

resource "aws_kms_key" "pass_literal_tags" {
  description         = "fixture"
  enable_key_rotation = true

  tags = {
    Name        = "fixture"
    Environment = "dev"
  }
}

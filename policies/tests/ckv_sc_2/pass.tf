# tflint-ignore-file: terraform_unused_declarations, terraform_required_providers, terraform_required_version, terraform_standard_module_structure
# Fixture of CKV_SC_2: resources named pass_* must PASS.

# checkov:skip=CKV_SC_2: state backend key is shared by dev and prod (ADR-0011) and legitimately has no Environment tag.
resource "aws_kms_key" "pass_shared_state_backend" {
  description         = "fixture"
  enable_key_rotation = true

  tags = {
    Name = "state-backend-key"
  }
}

resource "aws_kms_key" "pass_literal_tags" {
  description         = "fixture"
  enable_key_rotation = true

  tags = {
    Name        = "fixture"
    Environment = "dev"
  }
}

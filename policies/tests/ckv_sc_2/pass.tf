# Fixture of CKV_SC_2: resources named pass_* must PASS.

resource "aws_kms_key" "pass_literal_tags" {
  description         = "fixture"
  enable_key_rotation = true

  tags = {
    Name        = "fixture"
    Environment = "dev"
  }
}

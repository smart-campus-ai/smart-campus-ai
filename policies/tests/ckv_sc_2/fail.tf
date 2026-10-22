# Fixture of CKV_SC_2: resources named fail_* must FAIL.

resource "aws_kms_key" "fail_no_tags" {
  description         = "fixture"
  enable_key_rotation = true
}

resource "aws_kms_key" "fail_tags_without_environment" {
  description         = "fixture"
  enable_key_rotation = true

  tags = {
    Name  = "fixture"
    Owner = "qa"
  }
}

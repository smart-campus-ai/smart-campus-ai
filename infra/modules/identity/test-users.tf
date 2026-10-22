# Development and demo only (enable_test_users). Passwords are generated here, stored in SSM as SecureString
# (CMK) and never exposed as outputs. They also live in the OpenTofu state, which is encrypted (encryption block).
resource "random_password" "test_user" {
  for_each = local.test_users

  length      = 24
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  min_special = 1
}

resource "aws_ssm_parameter" "test_user_password" {
  for_each = local.test_users

  name        = "${local.test_users_ssm_prefix}/${each.key}/password"
  description = "Temporary password of the test user ${each.key}."
  type        = "SecureString"
  key_id      = var.test_users_kms_key_arn
  value       = random_password.test_user[each.key].result

  tags = var.tags
}

resource "aws_cognito_user" "test" {
  for_each = local.test_users

  user_pool_id       = aws_cognito_user_pool.this.id
  username           = each.value.email
  temporary_password = random_password.test_user[each.key].result
  message_action     = "SUPPRESS"
  attributes         = { email = each.value.email, email_verified = "true" }

  # The password changes at first sign-in; the generated one must not be re-applied.
  lifecycle {
    ignore_changes = [temporary_password]
  }
}

resource "aws_cognito_user_in_group" "test" {
  for_each = local.test_users

  user_pool_id = aws_cognito_user_pool.this.id
  group_name   = aws_cognito_user_group.this[each.value.group].name
  username     = aws_cognito_user.test[each.key].username
}

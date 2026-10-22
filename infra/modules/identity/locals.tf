data "aws_region" "current" {}

locals {
  name = "${var.name_prefix}-users"

  domain_prefix = coalesce(var.domain_prefix, "${var.name_prefix}-auth")

  # Admin MFA is enforced outside Cognito (the pool can only make MFA optional or required for everyone):
  # the pool offers TOTP and the API handlers reject admin tokens issued without it (ADR to be written).
  groups = {
    student = {
      description = "Students: report and follow their own tickets, use the assistant."
      precedence  = 10
    }
    admin = {
      description = "Administrators: manage the ticket lifecycle and read KPIs. A second factor (TOTP) is required."
      precedence  = 1
    }
  }

  test_users = var.enable_test_users ? var.test_users : {}

  test_users_ssm_prefix = "/${var.name_prefix}/identity/test-users"
}

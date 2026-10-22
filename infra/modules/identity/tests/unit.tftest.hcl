mock_provider "aws" {
  override_data {
    target = data.aws_region.current
    values = {
      region = "eu-west-3"
    }
  }

  # Computed attributes are unknown at plan time; the groups, client, domain and outputs reference the pool.
  # Fake documentation account ID.
  override_resource {
    target = aws_cognito_user_pool.this
    values = {
      id       = "eu-west-3_AbCdEfGhI"
      arn      = "arn:aws:cognito-idp:eu-west-3:123456789012:userpool/eu-west-3_AbCdEfGhI"
      endpoint = "cognito-idp.eu-west-3.amazonaws.com/eu-west-3_AbCdEfGhI"
    }
  }

  override_resource {
    target = aws_cognito_user_pool_client.spa
    values = {
      id = "1h57kf5cpq17m0eml12EXAMPLE"
    }
  }
}

mock_provider "random" {}

variables {
  name_prefix   = "sc-dev"
  callback_urls = ["https://d1234567890abc.cloudfront.net/callback"]
  logout_urls   = ["https://d1234567890abc.cloudfront.net/"]
}

# EN31-AC1: groups student and admin exist
run "en31_ac1_groups" {
  command = plan

  assert {
    condition     = toset(keys(aws_cognito_user_group.this)) == toset(["student", "admin"])
    error_message = "The user pool must have exactly the groups student and admin."
  }

  assert {
    condition     = aws_cognito_user_group.this["admin"].name == "admin" && aws_cognito_user_group.this["student"].name == "student"
    error_message = "Group names must match the cognito:groups claim values student and admin."
  }

  assert {
    condition     = aws_cognito_user_group.this["admin"].precedence < aws_cognito_user_group.this["student"].precedence
    error_message = "admin must take precedence over student."
  }

  assert {
    condition     = toset(output.group_names) == toset(["student", "admin"])
    error_message = "group_names output must list both groups."
  }
}

# EN31-AC1: pool basics (e-mail sign-in, strong password, deletion protection, hosted domain)
run "en31_ac1_pool_baseline" {
  command = plan

  assert {
    condition     = aws_cognito_user_pool.this.name == "sc-dev-users"
    error_message = "The pool name must be <name_prefix>-users."
  }

  assert {
    condition     = contains(aws_cognito_user_pool.this.username_attributes, "email")
    error_message = "E-mail must be the sign-in identifier."
  }

  assert {
    condition     = aws_cognito_user_pool.this.deletion_protection == "ACTIVE"
    error_message = "Deletion protection must be active by default."
  }

  assert {
    condition = alltrue([
      one(aws_cognito_user_pool.this.password_policy).minimum_length >= 12,
      one(aws_cognito_user_pool.this.password_policy).require_lowercase,
      one(aws_cognito_user_pool.this.password_policy).require_uppercase,
      one(aws_cognito_user_pool.this.password_policy).require_numbers,
      one(aws_cognito_user_pool.this.password_policy).require_symbols,
    ])
    error_message = "The password policy must require 12+ characters with all four character classes."
  }

  assert {
    condition     = one(aws_cognito_user_pool.this.admin_create_user_config).allow_admin_create_user_only
    error_message = "Self sign-up must be disabled by default."
  }

  assert {
    condition     = aws_cognito_user_pool_domain.this.domain == "sc-dev-auth"
    error_message = "The hosted domain prefix must default to <name_prefix>-auth."
  }

  assert {
    condition     = output.hosted_ui_base_url == "https://sc-dev-auth.auth.eu-west-3.amazoncognito.com"
    error_message = "hosted_ui_base_url must be the Cognito hosted domain."
  }
}

# EN31-AC2: only the code flow, no secret, callback and logout URLs = CloudFront URL
run "en31_ac2_spa_client_pkce" {
  command = plan

  assert {
    condition     = aws_cognito_user_pool_client.spa.allowed_oauth_flows == toset(["code"]) && aws_cognito_user_pool_client.spa.allowed_oauth_flows_user_pool_client
    error_message = "Only the authorization code flow may be allowed."
  }

  assert {
    condition     = aws_cognito_user_pool_client.spa.generate_secret == false
    error_message = "The SPA client must not have a client secret."
  }

  assert {
    condition     = aws_cognito_user_pool_client.spa.callback_urls == toset(["https://d1234567890abc.cloudfront.net/callback"])
    error_message = "callback_urls must be the CloudFront URL."
  }

  assert {
    condition     = aws_cognito_user_pool_client.spa.logout_urls == toset(["https://d1234567890abc.cloudfront.net/"])
    error_message = "logout_urls must be the CloudFront URL."
  }

  assert {
    condition     = !contains(aws_cognito_user_pool_client.spa.explicit_auth_flows, "ALLOW_USER_PASSWORD_AUTH") && !contains(aws_cognito_user_pool_client.spa.explicit_auth_flows, "ALLOW_ADMIN_USER_PASSWORD_AUTH")
    error_message = "Plain password authentication flows must not be enabled."
  }

  assert {
    condition     = aws_cognito_user_pool_client.spa.enable_token_revocation && aws_cognito_user_pool_client.spa.prevent_user_existence_errors == "ENABLED"
    error_message = "Token revocation and user existence error prevention must be enabled."
  }
}

run "en31_ac2_callback_url_rejects_wildcard" {
  command = plan

  variables {
    callback_urls = ["https://*.cloudfront.net/callback"]
  }

  expect_failures = [var.callback_urls]
}

run "en31_ac2_callback_url_rejects_plain_http" {
  command = plan

  variables {
    callback_urls = ["http://d1234567890abc.cloudfront.net/callback"]
  }

  expect_failures = [var.callback_urls]
}

run "en31_ac2_logout_url_rejects_wildcard" {
  command = plan

  variables {
    logout_urls = ["https://*.cloudfront.net/"]
  }

  expect_failures = [var.logout_urls]
}

# EN31-AC3: access token at most 60 minutes, refresh token rotation enabled
run "en31_ac3_token_validity_and_rotation" {
  command = plan

  assert {
    condition     = aws_cognito_user_pool_client.spa.access_token_validity <= 60 && one(aws_cognito_user_pool_client.spa.token_validity_units).access_token == "minutes"
    error_message = "The access token must be valid 60 minutes at most."
  }

  assert {
    condition     = one(aws_cognito_user_pool_client.spa.refresh_token_rotation).feature == "ENABLED"
    error_message = "Refresh token rotation must be enabled."
  }
}

run "en31_ac3_access_token_validity_rejects_over_60_minutes" {
  command = plan

  variables {
    access_token_validity_minutes = 120
  }

  expect_failures = [var.access_token_validity_minutes]
}

run "en31_ac3_grace_period_rejects_over_60_seconds" {
  command = plan

  variables {
    refresh_token_rotation_grace_period_seconds = 120
  }

  expect_failures = [var.refresh_token_rotation_grace_period_seconds]
}

# EN31-AC4: MFA is optional at pool level (TOTP offered), enforced for admin outside Cognito (ADR)
run "en31_ac4_mfa_totp_available" {
  command = plan

  assert {
    condition     = aws_cognito_user_pool.this.mfa_configuration == "OPTIONAL"
    error_message = "Pool MFA must be OPTIONAL: Cognito cannot require it for a single group."
  }

  assert {
    condition     = one(aws_cognito_user_pool.this.software_token_mfa_configuration).enabled
    error_message = "TOTP must be enabled so that admins can enrol a second factor."
  }

  assert {
    condition     = strcontains(aws_cognito_user_group.this["admin"].description, "second factor")
    error_message = "The admin group must document the second factor requirement."
  }
}

# EN31-AC5: threat protection behind a variable
run "en31_ac5_threat_protection_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_cognito_user_pool.this.user_pool_add_ons) == 0 && aws_cognito_user_pool.this.user_pool_tier == "ESSENTIALS"
    error_message = "Threat protection must be off by default."
  }
}

run "en31_ac5_threat_protection_enabled" {
  command = plan

  variables {
    enable_threat_protection = true
  }

  assert {
    condition     = one(aws_cognito_user_pool.this.user_pool_add_ons).advanced_security_mode == "ENFORCED"
    error_message = "Threat protection must be enforced when enabled."
  }

  assert {
    condition     = aws_cognito_user_pool.this.user_pool_tier == "PLUS"
    error_message = "Threat protection requires the Plus feature plan."
  }
}

run "en31_ac5_threat_protection_mode_rejects_unknown" {
  command = plan

  variables {
    threat_protection_mode = "OFF"
  }

  expect_failures = [var.threat_protection_mode]
}

# EN31-AC6: no test user unless enabled
run "en31_ac6_no_test_users_by_default" {
  command = plan

  assert {
    condition     = length(aws_cognito_user.test) == 0 && length(aws_ssm_parameter.test_user_password) == 0 && length(random_password.test_user) == 0
    error_message = "No test user may be created by default."
  }
}

run "en31_ac6_test_users_ignored_when_disabled" {
  command = plan

  variables {
    enable_test_users = false
    test_users = {
      student1 = { email = "student1@example.com", group = "student" }
    }
  }

  assert {
    condition     = length(aws_cognito_user.test) == 0
    error_message = "test_users must be ignored while enable_test_users is false (prod)."
  }
}

run "en31_ac6_test_users_enabled" {
  command = plan

  variables {
    enable_test_users      = true
    test_users_kms_key_arn = "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000"
    test_users = {
      student1 = { email = "student1@example.com", group = "student" }
      admin1   = { email = "admin1@example.com", group = "admin" }
    }
  }

  assert {
    condition     = toset(keys(aws_cognito_user.test)) == toset(["student1", "admin1"])
    error_message = "One Cognito user per test user entry is expected."
  }

  assert {
    condition     = alltrue([for u in aws_cognito_user.test : u.message_action == "SUPPRESS"])
    error_message = "No invitation e-mail may be sent to test users."
  }

  assert {
    condition     = aws_cognito_user_in_group.test["admin1"].group_name == "admin" && aws_cognito_user_in_group.test["student1"].group_name == "student"
    error_message = "Test users must be members of their group."
  }

  assert {
    condition = alltrue([
      for p in aws_ssm_parameter.test_user_password :
      p.type == "SecureString" && p.key_id == "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000"
    ])
    error_message = "Test user passwords must be SecureString parameters encrypted with the CMK."
  }

  assert {
    condition     = aws_ssm_parameter.test_user_password["admin1"].name == "/sc-dev/identity/test-users/admin1/password"
    error_message = "Test user passwords must be stored under /<name_prefix>/identity/test-users/<key>/password."
  }

  assert {
    condition     = alltrue([for r in random_password.test_user : r.length >= 20])
    error_message = "Generated test passwords must be at least 20 characters long."
  }
}

run "en31_ac6_test_users_require_kms_key" {
  command = plan

  variables {
    enable_test_users = true
    test_users = {
      student1 = { email = "student1@example.com", group = "student" }
    }
  }

  expect_failures = [var.test_users_kms_key_arn]
}

run "en31_ac6_test_users_reject_unknown_group" {
  command = plan

  variables {
    test_users = {
      user1 = { email = "user1@example.com", group = "superuser" }
    }
  }

  expect_failures = [var.test_users]
}

# Outputs
run "en31_outputs_pool_client_issuer" {
  command = plan

  assert {
    condition     = output.user_pool_id == "eu-west-3_AbCdEfGhI" && output.user_pool_arn == "arn:aws:cognito-idp:eu-west-3:123456789012:userpool/eu-west-3_AbCdEfGhI"
    error_message = "user_pool_id and user_pool_arn must come from the pool."
  }

  assert {
    condition     = output.client_id == "1h57kf5cpq17m0eml12EXAMPLE"
    error_message = "client_id must come from the SPA client."
  }

  assert {
    condition     = output.issuer_url == "https://cognito-idp.eu-west-3.amazonaws.com/eu-west-3_AbCdEfGhI"
    error_message = "issuer_url must be the Cognito issuer of the pool."
  }
}

# Variable validations
run "en31_validation_name_prefix" {
  command = plan

  variables {
    name_prefix = "SC_Dev"
  }

  expect_failures = [var.name_prefix]
}

run "en31_validation_password_length" {
  command = plan

  variables {
    password_minimum_length = 8
  }

  expect_failures = [var.password_minimum_length]
}

run "en31_validation_domain_prefix_reserved_word" {
  command = plan

  variables {
    domain_prefix = "sc-cognito"
  }

  expect_failures = [var.domain_prefix]
}

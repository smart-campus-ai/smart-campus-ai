resource "aws_cognito_user_pool" "this" {
  name                = local.name
  deletion_protection = var.deletion_protection ? "ACTIVE" : "INACTIVE"

  # Threat protection is only available in the Plus feature plan.
  user_pool_tier = var.enable_threat_protection ? "PLUS" : "ESSENTIALS"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  # MFA is optional at pool level: Cognito cannot require it for one group only. TOTP is offered to everyone and
  # enforced for the admin group by the token checks described in the README.
  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length                   = var.password_minimum_length
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = var.temporary_password_validity_days
  }

  admin_create_user_config {
    allow_admin_create_user_only = !var.allow_self_signup
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  dynamic "user_pool_add_ons" {
    for_each = var.enable_threat_protection ? [1] : []

    content {
      advanced_security_mode = var.threat_protection_mode
    }
  }

  tags = var.tags
}

resource "aws_cognito_user_group" "this" {
  for_each = local.groups

  name         = each.key
  user_pool_id = aws_cognito_user_pool.this.id
  description  = each.value.description
  precedence   = each.value.precedence
}

# No custom domain (architecture v3): Cognito hosted domain only.
resource "aws_cognito_user_pool_domain" "this" {
  domain       = local.domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}

# Public client of the SPA: authorization code + PKCE, no client secret.
resource "aws_cognito_user_pool_client" "spa" {
  name         = "${local.name}-spa"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = var.oauth_scopes
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls
  supported_identity_providers         = var.supported_identity_providers

  explicit_auth_flows           = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity  = var.access_token_validity_minutes
  id_token_validity      = var.id_token_validity_minutes
  refresh_token_validity = var.refresh_token_validity_days

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  refresh_token_rotation {
    feature                    = "ENABLED"
    retry_grace_period_seconds = var.refresh_token_rotation_grace_period_seconds
  }
}

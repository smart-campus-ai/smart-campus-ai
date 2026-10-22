variable "name_prefix" {
  description = "Prefix of every resource name, in the form sc-<env> (for example \"sc-dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "callback_urls" {
  description = "OAuth callback URLs of the SPA app client: the CloudFront URL of the environment (EN-21). HTTPS only, no wildcard; http://localhost is accepted for local development."
  type        = list(string)

  validation {
    condition     = length(var.callback_urls) >= 1
    error_message = "callback_urls must contain at least one URL."
  }

  validation {
    condition     = alltrue([for url in var.callback_urls : can(regex("^(https://[A-Za-z0-9.-]+(:[0-9]+)?|http://localhost(:[0-9]+)?)(/[^*#?]*)?$", url))])
    error_message = "Every callback_urls entry must be an https:// URL (or http://localhost) without wildcard, query string or fragment."
  }
}

variable "logout_urls" {
  description = "Sign-out URLs of the SPA app client: the CloudFront URL of the environment (EN-21). HTTPS only, no wildcard; http://localhost is accepted for local development."
  type        = list(string)

  validation {
    condition     = length(var.logout_urls) >= 1
    error_message = "logout_urls must contain at least one URL."
  }

  validation {
    condition     = alltrue([for url in var.logout_urls : can(regex("^(https://[A-Za-z0-9.-]+(:[0-9]+)?|http://localhost(:[0-9]+)?)(/[^*#?]*)?$", url))])
    error_message = "Every logout_urls entry must be an https:// URL (or http://localhost) without wildcard, query string or fragment."
  }
}

variable "domain_prefix" {
  description = "Prefix of the Cognito hosted domain (<prefix>.auth.<region>.amazoncognito.com). It is unique per region across all AWS accounts. Null uses \"<name_prefix>-auth\"."
  type        = string
  default     = null

  validation {
    condition     = var.domain_prefix == null || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.domain_prefix))
    error_message = "domain_prefix must be 1 to 63 characters: lowercase letters, digits and hyphens, not starting or ending with a hyphen."
  }

  validation {
    condition     = var.domain_prefix == null || !can(regex("aws|amazon|cognito", var.domain_prefix))
    error_message = "domain_prefix must not contain the reserved words aws, amazon or cognito."
  }
}

variable "deletion_protection" {
  description = "Protect the user pool against deletion. Keep true everywhere except short-lived sandboxes: deleting a pool deletes every user."
  type        = bool
  default     = true
}

variable "allow_self_signup" {
  description = "Let anyone create an account from the hosted UI. Off: accounts are created by an administrator or by federation (Entra ID, US06)."
  type        = bool
  default     = false
}

variable "password_minimum_length" {
  description = "Minimum password length. Upper case, lower case, digit and symbol are always required."
  type        = number
  default     = 12

  validation {
    condition     = var.password_minimum_length >= 12 && var.password_minimum_length <= 99 && floor(var.password_minimum_length) == var.password_minimum_length
    error_message = "password_minimum_length must be a whole number between 12 and 99."
  }
}

variable "temporary_password_validity_days" {
  description = "Number of days an administrator-created account can be activated with its temporary password."
  type        = number
  default     = 7

  validation {
    condition     = var.temporary_password_validity_days >= 1 && var.temporary_password_validity_days <= 365 && floor(var.temporary_password_validity_days) == var.temporary_password_validity_days
    error_message = "temporary_password_validity_days must be a whole number between 1 and 365."
  }
}

variable "enable_threat_protection" {
  description = "Enable Cognito threat protection (advanced security: compromised credentials and adaptive authentication). Requires the Plus feature plan, which is billed per monthly active user: leave off where the account does not provide it."
  type        = bool
  default     = false
}

variable "threat_protection_mode" {
  description = "Threat protection mode when enable_threat_protection is true: AUDIT only records risk, ENFORCED also blocks or challenges risky sign-ins."
  type        = string
  default     = "ENFORCED"

  validation {
    condition     = contains(["AUDIT", "ENFORCED"], var.threat_protection_mode)
    error_message = "threat_protection_mode must be AUDIT or ENFORCED."
  }
}

variable "oauth_scopes" {
  description = "OAuth scopes the SPA app client may request."
  type        = list(string)
  default     = ["openid", "email", "profile"]

  validation {
    condition     = length(var.oauth_scopes) >= 1 && alltrue([for scope in var.oauth_scopes : contains(["openid", "email", "profile", "phone", "aws.cognito.signin.user.admin"], scope)])
    error_message = "oauth_scopes must be a non-empty list of: openid, email, profile, phone, aws.cognito.signin.user.admin."
  }
}

variable "supported_identity_providers" {
  description = "Identity providers enabled on the SPA app client. Add the Entra ID provider name here once federation is configured (US06)."
  type        = list(string)
  default     = ["COGNITO"]

  validation {
    condition     = length(var.supported_identity_providers) >= 1
    error_message = "supported_identity_providers must contain at least one provider."
  }
}

variable "access_token_validity_minutes" {
  description = "Validity of the access token, in minutes (architecture v3: 60 at most)."
  type        = number
  default     = 60

  validation {
    condition     = var.access_token_validity_minutes >= 5 && var.access_token_validity_minutes <= 60 && floor(var.access_token_validity_minutes) == var.access_token_validity_minutes
    error_message = "access_token_validity_minutes must be a whole number between 5 and 60."
  }
}

variable "id_token_validity_minutes" {
  description = "Validity of the ID token, in minutes."
  type        = number
  default     = 60

  validation {
    condition     = var.id_token_validity_minutes >= 5 && var.id_token_validity_minutes <= 60 && floor(var.id_token_validity_minutes) == var.id_token_validity_minutes
    error_message = "id_token_validity_minutes must be a whole number between 5 and 60."
  }
}

variable "refresh_token_validity_days" {
  description = "Validity of the refresh token, in days."
  type        = number
  default     = 30

  validation {
    condition     = var.refresh_token_validity_days >= 1 && var.refresh_token_validity_days <= 365 && floor(var.refresh_token_validity_days) == var.refresh_token_validity_days
    error_message = "refresh_token_validity_days must be a whole number between 1 and 365."
  }
}

variable "refresh_token_rotation_grace_period_seconds" {
  description = "Time during which the rotated-out refresh token stays valid, to allow client retries. 0 invalidates it immediately."
  type        = number
  default     = 0

  validation {
    condition     = var.refresh_token_rotation_grace_period_seconds >= 0 && var.refresh_token_rotation_grace_period_seconds <= 60 && floor(var.refresh_token_rotation_grace_period_seconds) == var.refresh_token_rotation_grace_period_seconds
    error_message = "refresh_token_rotation_grace_period_seconds must be a whole number between 0 and 60."
  }
}

variable "enable_test_users" {
  description = "Create the users described in test_users, with a generated temporary password stored in SSM Parameter Store. Development only: never enable in prod."
  type        = bool
  default     = false
}

variable "test_users" {
  description = "Test users by stable key (lowercase letters, digits, hyphens). Created only when enable_test_users is true. The password is generated, never an input."
  type = map(object({
    email = string
    group = string
  }))
  default = {}

  validation {
    condition     = alltrue([for key in keys(var.test_users) : can(regex("^[a-z0-9][a-z0-9-]{0,30}$", key))])
    error_message = "test_users keys must be 1 to 31 characters: lowercase letters, digits and hyphens."
  }

  validation {
    condition     = alltrue([for user in values(var.test_users) : contains(["student", "admin"], user.group)])
    error_message = "test_users group must be \"student\" or \"admin\"."
  }

  validation {
    condition     = alltrue([for user in values(var.test_users) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", user.email))])
    error_message = "test_users email must be a valid e-mail address."
  }
}

variable "test_users_kms_key_arn" {
  description = "ARN of the customer-managed KMS key (EN-14, data domain) that encrypts the SecureString parameters holding the test user passwords. Required when enable_test_users is true."
  type        = string
  default     = null

  validation {
    condition     = var.test_users_kms_key_arn == null || can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]{36}$", var.test_users_kms_key_arn))
    error_message = "test_users_kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account id>:key/<key id>)."
  }

  validation {
    condition     = !var.enable_test_users || var.test_users_kms_key_arn != null
    error_message = "test_users_kms_key_arn is required when enable_test_users is true."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

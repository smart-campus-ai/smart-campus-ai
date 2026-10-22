variable "name_prefix" {
  description = "Project prefix of the CI identity resources (roles <prefix>-gha-*, policies <prefix>-ci-boundary and <prefix>-<env>-workload-boundary). Per-environment resources are scoped by <prefix>-dev-* and <prefix>-prod-*, so this is the project prefix (for example \"sc\"), not an environment prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the CI roles, as <owner>/<repo>. It is pinned verbatim in the \"sub\" claim of every trust policy, so wildcards are refused."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$", var.github_repository))
    error_message = "github_repository must look like <owner>/<repo> (letters, digits, dots, underscores and hyphens), without wildcards."
  }
}

variable "allowed_regions" {
  description = "Regions in which the apply roles may manage name-scoped resources: the main region plus us-east-1 for CloudFront-scoped WAF and ACM. Used to build regional ARNs."
  type        = list(string)

  validation {
    condition     = length(var.allowed_regions) >= 1
    error_message = "allowed_regions must contain at least one region."
  }

  validation {
    condition     = alltrue([for r in var.allowed_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", r))])
    error_message = "Every allowed_regions entry must look like us-east-1, without wildcards."
  }
}

variable "state_bucket_arn" {
  description = "ARN of the shared OpenTofu state bucket (output of the state-backend module). The apply roles get read/write on <env>/* only; the plan role gets read on dev/* only and no write."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_arn))
    error_message = "state_bucket_arn must be a bucket ARN (arn:<partition>:s3:::<bucket>), without a key suffix or wildcard."
  }
}

variable "state_kms_key_arn" {
  description = "ARN of the state KMS key (output of the state-backend module). The CI roles get usage only; destructive actions are denied."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]{36}$", var.state_kms_key_arn))
    error_message = "state_kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account id>:key/<key id>), not an alias."
  }
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. Set to false when the account already has one (an account holds a single provider per URL) and pass its ARN in existing_oidc_provider_arn."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of the existing GitHub OIDC identity provider (token.actions.githubusercontent.com). Required when create_oidc_provider is false, must be null otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.existing_oidc_provider_arn == null || can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.existing_oidc_provider_arn))
    error_message = "existing_oidc_provider_arn must be the ARN of the GitHub provider: arn:<partition>:iam::<account id>:oidc-provider/token.actions.githubusercontent.com."
  }

  validation {
    condition     = var.create_oidc_provider || var.existing_oidc_provider_arn != null
    error_message = "existing_oidc_provider_arn is required when create_oidc_provider is false."
  }

  validation {
    condition     = !var.create_oidc_provider || var.existing_oidc_provider_arn == null
    error_message = "existing_oidc_provider_arn must be null when create_oidc_provider is true."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

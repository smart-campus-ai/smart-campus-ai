variable "aws_region" {
  description = "Region of the state bucket and of the state KMS key."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like us-east-1."
  }
}

variable "name_prefix" {
  description = "Project prefix of the shared state resources (the bucket serves every environment, ADR-0011)."
  type        = string
  default     = "sc"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "admin_principal_arns" {
  description = "IAM role or user ARNs that administer the state KMS key and the recovery settings of the state bucket: the human running this bootstrap plus a break-glass principal. Never a CI role. No default: set it in terraform.tfvars (see terraform.tfvars.example)."
  type        = list(string)

  validation {
    condition     = length(var.admin_principal_arns) >= 1
    error_message = "admin_principal_arns must contain at least one principal."
  }

  validation {
    condition     = alltrue([for arn in var.admin_principal_arns : can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:(role|user)/[^*?]+$", arn))])
    error_message = "Every admin_principal_arns entry must be an IAM role or user ARN (arn:<partition>:iam::<account id>:role/<name> or user/<name>), without wildcards."
  }
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the CI roles, as <owner>/<repo>. Pinned verbatim in the \"sub\" claim of the trust policies."
  type        = string
  default     = "smart-campus-ai/smart-campus-ai"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$", var.github_repository))
    error_message = "github_repository must look like <owner>/<repo>, without wildcards."
  }
}

variable "allowed_regions" {
  description = "Regions in which the apply roles may manage resources: the main region plus us-east-1 for the CloudFront-scoped WAF and ACM."
  type        = list(string)
  default     = ["us-east-1"]

  validation {
    condition     = length(var.allowed_regions) >= 1 && alltrue([for r in var.allowed_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", r))])
    error_message = "allowed_regions must contain at least one region, each looking like us-east-1, without wildcards."
  }

  # The state bucket and the state key live in aws_region: the apply roles must be allowed to act there, otherwise the
  # aws:RequestedRegion condition of the Resource "*" statements would lock them out of their own backend.
  validation {
    condition     = contains(var.allowed_regions, var.aws_region)
    error_message = "allowed_regions must contain aws_region (the region of the state bucket and key)."
  }
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. Set to false when the account already has one (a single provider per URL is allowed) and pass its ARN in existing_oidc_provider_arn."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of the existing GitHub OIDC identity provider. Required when create_oidc_provider is false, must be null otherwise."
  type        = string
  default     = null
}

variable "owner" {
  description = "Value of the Owner tag."
  type        = string
  default     = "ops"

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty."
  }
}

variable "repository" {
  description = "Value of the Repository tag."
  type        = string
  default     = "smart-campus-ai"

  validation {
    condition     = length(trimspace(var.repository)) > 0
    error_message = "repository must not be empty."
  }
}

variable "data_classification" {
  description = "Value of the DataClassification tag. State files can hold sensitive attributes."
  type        = string
  default     = "confidential"

  validation {
    condition     = contains(["public", "internal", "confidential"], var.data_classification)
    error_message = "data_classification must be one of public, internal, confidential."
  }
}

variable "kms_deletion_window_in_days" {
  description = "Waiting period, in days, before the state KMS key is deleted after a deletion request."
  type        = number
  default     = 30
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days after which previous state versions are permanently deleted."
  type        = number
  default     = 90
}

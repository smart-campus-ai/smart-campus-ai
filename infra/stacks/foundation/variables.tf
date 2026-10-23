variable "env" {
  description = "Environment name."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "name_prefix" {
  description = "Prefix of every resource name: sc-<env>."
  type        = string

  validation {
    condition     = var.name_prefix == "sc-${var.env}"
    error_message = "name_prefix must be sc-<env> (for example sc-dev)."
  }
}

variable "aws_region" {
  description = "Default region of the stack."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like us-east-1."
  }
}

variable "state_kms_key_arn" {
  description = "ARN of the state KMS key (bootstrap output state_kms_key_arn), used by the OpenTofu state and plan encryption."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]{36}$", var.state_kms_key_arn))
    error_message = "state_kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}

variable "owner" {
  description = "Value of the Owner tag."
  type        = string
  default     = "ops"
}

variable "repository" {
  description = "Value of the Repository tag."
  type        = string
  default     = "smart-campus-ai"
}

variable "data_classification" {
  description = "Value of the DataClassification tag."
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["public", "internal", "confidential"], var.data_classification)
    error_message = "data_classification must be one of public, internal, confidential."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Permissions boundaries (ADR-0014 option B: workshop exception)
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_permissions_boundaries" {
  description = "Attach the project permissions boundary (workload_boundary_arn) to every IAM role. false only for the workshop exception of ADR-0014: the account cannot call iam:PutRolePermissionsBoundary. Then the account must be in boundary_exception_account_ids and the exception must not be expired, otherwise the plan fails."
  type        = bool
  default     = false
}

variable "workload_boundary_arn" {
  description = "ARN of the workload permissions boundary of this environment. Required when enable_permissions_boundaries is true, ignored otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.workload_boundary_arn == null || can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:policy/[^*?]+$", var.workload_boundary_arn))
    error_message = "workload_boundary_arn must be an IAM policy ARN (arn:<partition>:iam::<account id>:policy/<name>), without wildcards."
  }

  validation {
    condition     = !var.enable_permissions_boundaries || var.workload_boundary_arn != null
    error_message = "workload_boundary_arn is required when enable_permissions_boundaries is true."
  }
}

variable "boundary_exception_account_ids" {
  description = "AWS account IDs in which the boundary exception (enable_permissions_boundaries = false) is allowed: the workshop account only. Required while the exception is active."
  type        = list(string)
  default     = null

  validation {
    condition     = var.boundary_exception_account_ids == null || alltrue([for id in coalesce(var.boundary_exception_account_ids, []) : can(regex("^[0-9]{12}$", id))])
    error_message = "Every boundary_exception_account_ids entry must be a 12-digit AWS account ID."
  }
}

variable "boundary_exception_expires" {
  description = "Last day (YYYY-MM-DD, UTC, inclusive) of the boundary exception, capped at 2026-10-31 (end of the workshop, ADR-0014). Required while the exception is active; the plan fails after this day."
  type        = string
  default     = null

  validation {
    condition     = var.boundary_exception_expires == null || try(can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.boundary_exception_expires)) && timecmp("${var.boundary_exception_expires}T00:00:00Z", "2026-10-31T00:00:00Z") <= 0, false)
    error_message = "boundary_exception_expires must be a valid YYYY-MM-DD date not after 2026-10-31 (ADR-0014)."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# KMS keys (module kms-keys) and alerts key
# ---------------------------------------------------------------------------------------------------------------------

variable "admin_principal_arns" {
  description = "IAM role or user ARNs that administer the domain keys and the alerts key (ScheduleKeyDeletion, DisableKey, PutKeyPolicy). The identity that runs the apply that creates the keys must be one of them. Never a CI role. No default: pass it through TF_VAR_admin_principal_arns or -var (see envs/<env>/foundation.tfvars)."
  type        = list(string)

  validation {
    condition     = length(var.admin_principal_arns) >= 1
    error_message = "admin_principal_arns must contain at least one principal."
  }

  validation {
    condition     = alltrue([for arn in var.admin_principal_arns : can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:(role|user)/[^*?]+$", arn))])
    error_message = "Every admin_principal_arns entry must be an IAM role or user ARN (arn:<partition>:iam::<account id>:role/<name> or user/<name>), without wildcards. They must belong to this account (checked at plan)."
  }
}

variable "kms_deletion_window_in_days" {
  description = "Waiting period, in days, before a key is deleted after a deletion request (7 to 30). Must be 30 in prod."
  type        = number

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30 && floor(var.kms_deletion_window_in_days) == var.kms_deletion_window_in_days
    error_message = "kms_deletion_window_in_days must be a whole number between 7 and 30."
  }

  validation {
    condition     = var.env != "prod" || var.kms_deletion_window_in_days == 30
    error_message = "kms_deletion_window_in_days must be 30 in prod."
  }
}

variable "enable_bedrock" {
  description = "Let Amazon Bedrock use the ai key for the Knowledge Bases of this account (aws:SourceAccount + aws:SourceArn knowledge-base/*, the generated ID cannot be scoped to the prefix). Enabled before platform exists so the Knowledge Base can use the key at first apply."
  type        = bool
  default     = false
}

variable "cloudfront_distribution_arns" {
  description = "CloudFront distribution ARNs allowed to decrypt SSE-KMS buckets through their origin access control (data key). Empty until the platform stack has created the distribution: fill it in and re-apply foundation."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.cloudfront_distribution_arns : can(regex("^arn:aws(-[a-z]+)*:cloudfront::[0-9]{12}:distribution/[A-Z0-9]+$", arn))])
    error_message = "Every cloudfront_distribution_arns entry must be a distribution ARN (arn:<partition>:cloudfront::<account id>:distribution/<id>), without wildcards. It must also belong to this account (checked at plan)."
  }
}

variable "guardduty_malware_protection_role_arns" {
  description = "ARNs of the GuardDuty Malware Protection for S3 roles allowed to use the data key. Empty until the platform stack has created the roles: fill it in and re-apply foundation."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.guardduty_malware_protection_role_arns : can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:role/[^*?]+$", arn))])
    error_message = "Every guardduty_malware_protection_role_arns entry must be an IAM role ARN (arn:<partition>:iam::<account id>:role/<name>), without wildcards. It must also belong to this account (checked at plan)."
  }
}

variable "enable_deletion_alerts" {
  description = "Alert the ops alerts topic when a domain key is disabled, scheduled for deletion, loses its rotation or its alias, or has its policy rewritten. Needs CloudTrail management events (already provided by the workshop account)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------------------------------------------------
# Budget (module budget)
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_budget" {
  description = "Create the monthly AWS budget. Keep it false in the workshop account: its IAM role is denied budgets:*, so the apply would fail with Access Denied."
  type        = bool
  default     = false
}

variable "budget_monthly_limit_usd" {
  description = "Monthly cost limit of the budget, in USD. Required when enable_budget is true."
  type        = number
  default     = null

  validation {
    condition     = var.budget_monthly_limit_usd == null || var.budget_monthly_limit_usd > 0
    error_message = "budget_monthly_limit_usd must be strictly greater than 0."
  }

  validation {
    condition     = !var.enable_budget || var.budget_monthly_limit_usd != null
    error_message = "budget_monthly_limit_usd is required when enable_budget is true."
  }
}

variable "budget_notification_emails" {
  description = "Email addresses that receive the budget notifications directly, in addition to the alerts topic. PII: keep them out of the public repository (TF_VAR_budget_notification_emails)."
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "budget_enable_anomaly_detection" {
  description = "Create a Cost Anomaly Detection monitor and subscription that publish to the alerts topic. Only used when enable_budget is true."
  type        = bool
  default     = false
}

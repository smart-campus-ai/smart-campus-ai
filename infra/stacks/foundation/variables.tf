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

variable "guardduty_malware_protection_role_arns" {
  description = "ARNs of the GuardDuty Malware Protection for S3 roles allowed to use the data key. Empty until the platform stack has created the roles: fill it in and re-apply foundation."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.guardduty_malware_protection_role_arns : can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:role/[^*?]+$", arn))])
    error_message = "Every guardduty_malware_protection_role_arns entry must be an IAM role ARN (arn:<partition>:iam::<account id>:role/<name>), without wildcards. It must also belong to this account (checked at plan)."
  }
}

variable "manage_api_gateway_account" {
  description = "Create the IAM role that lets API Gateway push logs to CloudWatch Logs and register it in the API Gateway account settings. These settings exist once per account and region: true in one environment only (dev), false in the others that share the account. Without them a stage with logging enabled cannot be created."
  type        = bool
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

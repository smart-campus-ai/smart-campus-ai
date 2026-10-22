variable "name_prefix" {
  description = "Prefix of every resource name. The state bucket is shared by all environments (ADR-0011), so this is the project prefix (for example \"sc\"), not an environment prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "admin_principal_arns" {
  description = "IAM role or user ARNs that administer the state KMS key (including ScheduleKeyDeletion, DisableKey, PutKeyPolicy) and are the only principals allowed to change the recovery settings of the state bucket (versions, versioning, lifecycle, bucket policy). Use the bootstrap human and a break-glass role, never a CI role. The principals must exist and must include whoever runs the bootstrap apply."
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

variable "kms_deletion_window_in_days" {
  description = "Waiting period, in days, before the state KMS key is deleted after a deletion request."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30 && floor(var.kms_deletion_window_in_days) == var.kms_deletion_window_in_days
    error_message = "kms_deletion_window_in_days must be a whole number between 7 and 30."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days after which noncurrent object versions (previous states) are permanently deleted."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days
    error_message = "noncurrent_version_expiration_days must be a whole number greater than or equal to 1."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Number of days after which an incomplete multipart upload is aborted."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1 && floor(var.abort_incomplete_multipart_upload_days) == var.abort_incomplete_multipart_upload_days
    error_message = "abort_incomplete_multipart_upload_days must be a whole number greater than or equal to 1."
  }
}

variable "enable_access_logging" {
  description = "Deliver S3 server access logs of the state bucket to access_log_bucket_name. Off by default: no log bucket exists when the bootstrap runs."
  type        = bool
  default     = false
}

variable "access_log_bucket_name" {
  description = "Name of the existing bucket that receives the access logs. Required when enable_access_logging is true; the bucket must allow the S3 logging service to write to it."
  type        = string
  default     = null

  validation {
    condition     = var.access_log_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", coalesce(var.access_log_bucket_name, "invalid")))
    error_message = "access_log_bucket_name must be a valid S3 bucket name (3 to 63 characters: lowercase letters, digits, dots and hyphens)."
  }

  validation {
    condition     = !var.enable_access_logging || var.access_log_bucket_name != null
    error_message = "access_log_bucket_name is required when enable_access_logging is true."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

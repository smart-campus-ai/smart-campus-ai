variable "name_prefix" {
  description = "Prefix of every resource name, in the form sc-<env> (for example \"sc-dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

# ---------------------------------------------------------------------------
# Switches. Every service is off by default: the workshop account may already provide it (EN-11), and in a shared
# account only one stack may enable a given account-level service. The values come from the environment tfvars.
# ---------------------------------------------------------------------------

variable "enable_cloudtrail" {
  description = "Create the multi-region CloudTrail trail (log file validation, KMS) and its CloudWatch Logs integration. Requires kms_key_arn, permissions_boundary_arn and cloudwatch_log_retention_days."
  type        = bool
  default     = false
}

variable "enable_guardduty" {
  description = "Create the GuardDuty detector in the current region."
  type        = bool
  default     = false
}

variable "enable_guardduty_s3_protection" {
  description = "Enable the GuardDuty S3 data events feature (S3 protection) on the detector. Requires enable_guardduty."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_guardduty_s3_protection || var.enable_guardduty
    error_message = "enable_guardduty_s3_protection requires enable_guardduty."
  }
}

variable "enable_guardduty_malware_protection" {
  description = "Enable the GuardDuty malware protection for EBS volumes feature on the detector. Requires enable_guardduty. Malware Protection for S3 buckets is a per-bucket plan owned by the module that owns the bucket."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_guardduty_malware_protection || var.enable_guardduty
    error_message = "enable_guardduty_malware_protection requires enable_guardduty."
  }
}

variable "enable_securityhub" {
  description = "Enable Security Hub in the current region and subscribe to the AWS Foundational Security Best Practices standard. The controls need AWS Config recording to report findings."
  type        = bool
  default     = false
}

variable "enable_config" {
  description = "Create the AWS Config recorder and delivery channel. Delivery goes to the security log bucket, which is created when this flag or enable_cloudtrail is true. Requires kms_key_arn."
  type        = bool
  default     = false
}

variable "enable_config_service_linked_role" {
  description = "Create the AWS Config service-linked role (config.amazonaws.com). Defaults to false because the role can exist only once per account and creating it twice fails the apply; set it to true in the environment tfvars (EN-11) when the role does not exist yet. The recorder always uses this role. Only used when enable_config is true."
  type        = bool
  default     = false
}

variable "enable_cloudtrail_s3_data_events" {
  description = "Record S3 object-level data events (AWS::S3::Object) of the buckets listed in cloudtrail_s3_data_event_bucket_arns on the trail (Security Hub FSBP S3.22 and S3.23, CIS 3.8 and 3.9). Off by default: data events are billed per event. Requires enable_cloudtrail."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_cloudtrail_s3_data_events || var.enable_cloudtrail
    error_message = "enable_cloudtrail_s3_data_events requires enable_cloudtrail."
  }

  validation {
    condition     = !var.enable_cloudtrail_s3_data_events || length(var.cloudtrail_s3_data_event_bucket_arns) > 0
    error_message = "cloudtrail_s3_data_event_bucket_arns must list at least one bucket when enable_cloudtrail_s3_data_events is true."
  }
}

variable "cloudtrail_s3_data_event_bucket_arns" {
  description = "ARNs of the S3 buckets whose object-level events are recorded (for example the attachments bucket and the state bucket). Only used when enable_cloudtrail_s3_data_events is true."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.cloudtrail_s3_data_event_bucket_arns : can(regex("^arn:aws(-[a-z]+)*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", arn))])
    error_message = "cloudtrail_s3_data_event_bucket_arns must contain S3 bucket ARNs (arn:<partition>:s3:::<bucket name>), without object path."
  }
}

variable "enable_access_analyzer" {
  description = "Create the account-level IAM Access Analyzer in the current region (one account analyzer per region)."
  type        = bool
  default     = false
}

variable "enable_s3_account_public_access_block" {
  description = "Enable S3 Block Public Access on the whole account (all four settings)."
  type        = bool
  default     = false
}

variable "enable_ebs_default_encryption" {
  description = "Enable EBS encryption by default for the current region."
  type        = bool
  default     = false
}

variable "enable_iam_password_policy" {
  description = "Set the account IAM password policy (14 characters minimum, all character classes, 90-day expiry, 24 passwords of history)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Inputs required only by some switches.
# ---------------------------------------------------------------------------

variable "kms_key_arn" {
  description = "ARN of the logs KMS key (EN-14). It encrypts the security log bucket, the trail and the CloudTrail log group, and Config deliveries. Required when enable_cloudtrail or enable_config is true. Its key policy must allow cloudtrail.amazonaws.com, config.amazonaws.com (and the AWS Config service-linked role) and the CloudWatch Logs service of the region."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", coalesce(var.kms_key_arn, "invalid")))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account id>:key/<key id>), not an alias."
  }

  validation {
    condition     = !(var.enable_cloudtrail || var.enable_config) || var.kms_key_arn != null
    error_message = "kms_key_arn is required when enable_cloudtrail or enable_config is true."
  }
}

variable "permissions_boundary_arn" {
  description = "ARN of the project permissions boundary attached to the IAM role created by this module (CloudTrail to CloudWatch Logs). Required when enable_cloudtrail is true."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:policy/.+$", coalesce(var.permissions_boundary_arn, "invalid")))
    error_message = "permissions_boundary_arn must be an IAM policy ARN (arn:<partition>:iam::<account id>:policy/<name>)."
  }

  validation {
    condition     = !var.enable_cloudtrail || var.permissions_boundary_arn != null
    error_message = "permissions_boundary_arn is required when enable_cloudtrail is true."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Retention, in days, of the CloudTrail CloudWatch log group (dev 14, prod 90). Required when enable_cloudtrail is true. The long-term copy of the logs lives in the log bucket (log_bucket_expiration_days)."
  type        = number
  default     = null

  validation {
    condition     = var.cloudwatch_log_retention_days == null || contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], coalesce(var.cloudwatch_log_retention_days, 0))
    error_message = "cloudwatch_log_retention_days must be a retention value supported by CloudWatch Logs (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653)."
  }

  validation {
    condition     = !var.enable_cloudtrail || var.cloudwatch_log_retention_days != null
    error_message = "cloudwatch_log_retention_days is required when enable_cloudtrail is true."
  }
}

variable "log_bucket_expiration_days" {
  description = "Number of days after which trail and Config objects are deleted from the security log bucket."
  type        = number
  default     = 365

  validation {
    condition     = var.log_bucket_expiration_days >= 1 && floor(var.log_bucket_expiration_days) == var.log_bucket_expiration_days
    error_message = "log_bucket_expiration_days must be a whole number greater than or equal to 1."
  }
}

variable "log_bucket_noncurrent_version_expiration_days" {
  description = "Number of days after which noncurrent object versions are permanently deleted from the security log bucket."
  type        = number
  default     = 90

  validation {
    condition     = var.log_bucket_noncurrent_version_expiration_days >= 1 && floor(var.log_bucket_noncurrent_version_expiration_days) == var.log_bucket_noncurrent_version_expiration_days
    error_message = "log_bucket_noncurrent_version_expiration_days must be a whole number greater than or equal to 1."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Number of days after which an incomplete multipart upload is aborted in the security log bucket."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1 && floor(var.abort_incomplete_multipart_upload_days) == var.abort_incomplete_multipart_upload_days
    error_message = "abort_incomplete_multipart_upload_days must be a whole number greater than or equal to 1."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

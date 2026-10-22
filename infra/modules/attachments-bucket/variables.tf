variable "name_prefix" {
  description = "Prefix of every resource name, \"sc-<env>\" (for example \"sc-dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "kms_key_arn" {
  description = "ARN of the customer-managed KMS key (\"data\" key, EN-14) that encrypts the attachments. It is the bucket default key and the only key accepted by the bucket policy. Its key policy must let the account use it through IAM, and the malware protection role when enable_malware_protection is true."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-zA-Z-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account id>:key/<key id>), not an alias."
  }
}

variable "allowed_origins" {
  description = "Origins allowed to call the bucket from a browser (presigned POST and PUT uploads, GET downloads): the CloudFront URL of the SPA, plus http://localhost:<port> in dev. Wildcards are refused."
  type        = list(string)

  validation {
    condition     = length(var.allowed_origins) >= 1
    error_message = "allowed_origins must contain at least one origin."
  }

  validation {
    condition     = alltrue([for o in var.allowed_origins : can(regex("^(https://[^*/\\s]+|http://localhost(:[0-9]{1,5})?)$", o))])
    error_message = "Every allowed_origins entry must be an https:// origin or http://localhost[:port], without wildcard, path or trailing slash."
  }
}

variable "cors_max_age_seconds" {
  description = "Time, in seconds, browsers may cache the CORS preflight response."
  type        = number
  default     = 3000

  validation {
    condition     = var.cors_max_age_seconds >= 0 && var.cors_max_age_seconds <= 86400 && floor(var.cors_max_age_seconds) == var.cors_max_age_seconds
    error_message = "cors_max_age_seconds must be a whole number between 0 and 86400."
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

variable "noncurrent_version_expiration_days" {
  description = "Number of days after which noncurrent object versions are permanently deleted."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days
    error_message = "noncurrent_version_expiration_days must be a whole number greater than or equal to 1."
  }
}

variable "object_expiration_days" {
  description = "Retention of the attachments (GDPR): number of days after creation at which current objects expire, aligned with the ticket retention. Required, no default."
  type        = number
  nullable    = false

  validation {
    condition     = var.object_expiration_days >= 1 && floor(var.object_expiration_days) == var.object_expiration_days
    error_message = "object_expiration_days must be a whole number greater than or equal to 1."
  }
}

variable "quarantine_prefix" {
  description = "Key prefix where objects waiting for, or failing, the malware scan are kept (the area the presigned POST uploads to). Only used when quarantine_expiration_days is set."
  type        = string
  default     = "quarantine/"

  validation {
    condition     = can(regex("^[A-Za-z0-9!_.*'()/-]+/$", var.quarantine_prefix))
    error_message = "quarantine_prefix must be a key prefix ending with \"/\" (for example \"quarantine/\")."
  }
}

variable "quarantine_expiration_days" {
  description = "Number of days after which objects under quarantine_prefix expire. null disables the rule."
  type        = number
  default     = null

  validation {
    condition     = var.quarantine_expiration_days == null || (coalesce(var.quarantine_expiration_days, 1) >= 1 && floor(coalesce(var.quarantine_expiration_days, 1)) == coalesce(var.quarantine_expiration_days, 1))
    error_message = "quarantine_expiration_days must be null or a whole number greater than or equal to 1."
  }
}

variable "enable_malware_protection" {
  description = "Create the GuardDuty Malware Protection plan for S3 (with its service role) and deny reads of objects that are not tagged GuardDutyMalwareScanStatus=NO_THREATS_FOUND. Requires GuardDuty Malware Protection for S3 in the region (EN-11). Enabled by default so that unscanned objects are never served. Setting it to false removes the read deny and serves every object as is: only do it where the service is unavailable, with an ADR."
  type        = bool
  default     = true
}

variable "malware_protection_object_prefixes" {
  description = "Key prefixes scanned by the malware protection plan (at most 5). Empty scans the whole bucket."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.malware_protection_object_prefixes) <= 5
    error_message = "malware_protection_object_prefixes accepts at most 5 prefixes."
  }
}

variable "permissions_boundary_arn" {
  description = "ARN of the workload permissions boundary attached to the malware protection service role (github-oidc output workload_boundary_arns). Required when enable_malware_protection is true."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:policy/.+$", coalesce(var.permissions_boundary_arn, "invalid")))
    error_message = "permissions_boundary_arn must be an IAM policy ARN (arn:<partition>:iam::<account id>:policy/<name>)."
  }

  validation {
    condition     = !var.enable_malware_protection || var.permissions_boundary_arn != null
    error_message = "permissions_boundary_arn is required when enable_malware_protection is true."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

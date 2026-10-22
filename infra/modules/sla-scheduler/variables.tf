variable "name_prefix" {
  description = "Environment prefix of every resource name (sc-<env>, for example \"sc-dev\"). The schedule group is named <name_prefix>-sla."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "escalation_alias_arn" {
  description = "ARN of the \"live\" alias of the escalation Lambda function (arn:<partition>:lambda:<region>:<account id>:function:<name>:live). The scheduler execution role may invoke this ARN only, never the unqualified function or $LATEST."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:lambda:[a-z0-9-]+:[0-9]{12}:function:[A-Za-z0-9_-]{1,64}:live$", var.escalation_alias_arn))
    error_message = "escalation_alias_arn must be the ARN of the \"live\" alias of a function (arn:<partition>:lambda:<region>:<account id>:function:<name>:live), without wildcards, version number or $LATEST."
  }
}

variable "permissions_boundary_arn" {
  description = "ARN of the project permissions boundary policy attached to the scheduler execution role."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:policy/[^*?]+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be an IAM policy ARN (arn:<partition>:iam::<account id>:policy/<name>), without wildcards."
  }
}

variable "enable_dlq" {
  description = "Create the SQS dead-letter queue that receives the events of schedules whose target invocation failed after all retries (AC4). Schedules reference it through the dlq_arn output."
  type        = bool
  default     = true
}

variable "dlq_kms_key_arn" {
  description = "ARN of the customer-managed KMS key (EN-14) that encrypts the dead-letter queue. Required when enable_dlq is true, must be null otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.dlq_kms_key_arn == null || can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]{36}$", coalesce(var.dlq_kms_key_arn, "invalid")))
    error_message = "dlq_kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account id>:key/<key id>), not an alias."
  }

  validation {
    condition     = !var.enable_dlq || var.dlq_kms_key_arn != null
    error_message = "dlq_kms_key_arn is required when enable_dlq is true."
  }

  validation {
    condition     = var.enable_dlq || var.dlq_kms_key_arn == null
    error_message = "dlq_kms_key_arn must be null when enable_dlq is false."
  }
}

variable "dlq_message_retention_seconds" {
  description = "How long the dead-letter queue keeps a failed event, in seconds (60 to 1209600, that is 14 days). Events only carry a ticket identifier."
  type        = number
  default     = 1209600

  validation {
    condition     = var.dlq_message_retention_seconds >= 60 && var.dlq_message_retention_seconds <= 1209600 && floor(var.dlq_message_retention_seconds) == var.dlq_message_retention_seconds
    error_message = "dlq_message_retention_seconds must be a whole number between 60 and 1209600."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

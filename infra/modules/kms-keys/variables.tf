variable "name_prefix" {
  description = "Prefix of every resource name and alias, <project>-<env> (for example \"sc-dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Environment name, applied as the Environment tag on every key (the CI apply roles require it on kms:CreateKey)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}$", var.environment))
    error_message = "environment must be 2 to 15 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "keys" {
  description = "Customer managed keys to create, one per domain, keyed by domain name. The alias is alias/<name_prefix>-<domain>. The service grants below target the domains \"logs\", \"data\" and \"ai\" and need the matching key to exist. A key flagged edge = true additionally lets CloudFront use it through an origin access control, for any distribution of this account (aws:SourceArn ArnLike on the account's distributions): it exists so that the key can be created before the distribution, without a dependency on the stack that owns it. Flag only a key that encrypts nothing but buckets served by CloudFront, whose bucket policy pins the distribution."
  type = map(object({
    description = string
    edge        = optional(bool, false)
  }))
  default = {
    data = { description = "Encrypts application data at rest: DynamoDB tables, SQS queues, S3 buckets" }
    logs = { description = "Encrypts logs: CloudWatch Logs log groups, CloudTrail, AWS Config" }
    ai   = { description = "Encrypts the AI assistant data: Bedrock Knowledge Base sources and ingestion" }
  }

  validation {
    condition     = length(var.keys) >= 1
    error_message = "keys must define at least one key."
  }

  validation {
    condition     = alltrue([for domain in keys(var.keys) : can(regex("^[a-z][a-z0-9-]{1,19}$", domain))])
    error_message = "Every key name must be 2 to 20 characters: lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition     = alltrue([for k in var.keys : length(trimspace(k.description)) > 0 && length(k.description) <= 8192])
    error_message = "Every key description must be non-empty and at most 8192 characters."
  }

  validation {
    condition     = length([for k in var.keys : k if k.edge]) <= 1
    error_message = "At most one key may be flagged edge: the account-wide CloudFront grant is kept to a single, dedicated key."
  }

  validation {
    condition     = alltrue([for domain, k in var.keys : !k.edge || !contains(["data", "logs", "ai"], domain)])
    error_message = "The edge flag is refused on the data, logs and ai keys: they encrypt data that CloudFront must never be able to read. Use a dedicated domain (for example \"edge\")."
  }

  validation {
    condition = alltrue([
      for domain, enabled in {
        logs = var.enable_cloudwatch_logs || var.enable_cloudtrail || var.enable_config || var.enable_log_delivery
        data = length(var.cloudfront_distribution_arns) > 0 || length(var.guardduty_malware_protection_role_arns) > 0
        ai   = var.enable_bedrock
      } : !enabled || contains(keys(var.keys), domain)
    ])
    error_message = "Service grants are enabled for a domain whose key is not in keys: the logs grants need a \"logs\" key, the data grants a \"data\" key and the ai grants an \"ai\" key."
  }
}

variable "admin_principal_arns" {
  description = "IAM role or user ARNs that administer the keys (including ScheduleKeyDeletion, DisableKey, PutKeyPolicy). Use the bootstrap human and a break-glass role, never a CI role (CI roles read the keys through IAM, with the read-only actions delegated to the account root). The principals must exist, and must include whoever runs the apply that creates the keys."
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
  description = "Waiting period, in days, before a key is deleted after a deletion request. Must be 30 (the maximum) when environment is \"prod\"."
  type        = number

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30 && floor(var.kms_deletion_window_in_days) == var.kms_deletion_window_in_days
    error_message = "kms_deletion_window_in_days must be a whole number between 7 and 30."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# logs key grants
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_cloudwatch_logs" {
  description = "Let CloudWatch Logs use the logs key for log groups, only when the log group ARN matches the name patterns (encryption context)."
  type        = bool
  default     = false
}

variable "log_group_name_patterns" {
  description = "Log group name patterns, in addition to \"<name_prefix>-*\", that CloudWatch Logs may encrypt with the logs key (for example \"/aws/lambda/sc-dev-*\"). Each pattern needs at least 3 literal characters, may end with \"*\" and must contain \"<name_prefix>-\" (the account is shared by the environments)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.log_group_name_patterns : can(regex("^[A-Za-z0-9_./#-]{3,}[*]?$", p))])
    error_message = "Every log group name pattern must start with at least 3 literal characters (letters, digits and _ . / # -) and may only end with a \"*\"."
  }

  validation {
    condition     = alltrue([for p in var.log_group_name_patterns : can(regex("(^|[/_.#-])${var.name_prefix}-", p))])
    error_message = "Every log group name pattern must contain \"<name_prefix>-\" (for example \"/aws/lambda/sc-dev-*\"), otherwise the logs key opens to the other environments of the account."
  }
}

variable "enable_cloudtrail" {
  description = "Let CloudTrail use the logs key to encrypt trail log files (GenerateDataKey, restricted to trails of this account)."
  type        = bool
  default     = false
}

variable "enable_config" {
  description = "Let the AWS Config service-linked role use the logs key to deliver to S3. The service-linked role must already exist, otherwise the key policy is rejected."
  type        = bool
  default     = false
}

variable "enable_log_delivery" {
  description = "Let the vended logs delivery service (delivery.logs.amazonaws.com, used by WAF and API Gateway logs sent to S3) use the logs key, restricted to delivery sources of this account."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------------------------------------------------
# data key grants
# ---------------------------------------------------------------------------------------------------------------------

variable "cloudfront_distribution_arns" {
  description = "CloudFront distribution ARNs allowed to decrypt objects of SSE-KMS buckets through their origin access control (aws:SourceArn). Empty disables the statement."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.cloudfront_distribution_arns : can(regex("^arn:aws(-[a-z]+)*:cloudfront::[0-9]{12}:distribution/[A-Z0-9]+$", arn))])
    error_message = "Every cloudfront_distribution_arns entry must be a distribution ARN (arn:<partition>:cloudfront::<account id>:distribution/<id>), without wildcards."
  }
}

variable "guardduty_malware_protection_role_arns" {
  description = "ARNs of the IAM roles used by GuardDuty Malware Protection for S3 to scan and tag objects of SSE-KMS buckets. The roles must exist. Empty disables the statement."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.guardduty_malware_protection_role_arns : can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:role/[^*?]+$", arn))])
    error_message = "Every guardduty_malware_protection_role_arns entry must be an IAM role ARN without wildcards."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# ai key grants
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_bedrock" {
  description = "Let Amazon Bedrock use the ai key for the Knowledge Bases of this account (aws:SourceAccount + aws:SourceArn)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------------------------------------------------
# key protection alerts
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_deletion_alerts" {
  description = "Create an EventBridge rule that publishes to alert_topic_arn when ScheduleKeyDeletion, DisableKey, DisableKeyRotation or PutKeyPolicy is called on one of these keys, or DeleteAlias on one of their aliases. Needs CloudTrail management events (security baseline)."
  type        = bool
  default     = false
}

variable "alert_topic_arn" {
  description = "ARN of the SNS topic that receives the key deletion alerts. Required when enable_deletion_alerts is true. Its policy must allow events.amazonaws.com to publish (use the deletion_alert_rule_arn output as aws:SourceArn)."
  type        = string
  default     = null

  validation {
    condition     = var.alert_topic_arn == null || can(regex("^arn:aws(-[a-z]+)*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_.-]{1,256}$", coalesce(var.alert_topic_arn, "invalid")))
    error_message = "alert_topic_arn must be an SNS topic ARN."
  }

  validation {
    condition     = !var.enable_deletion_alerts || var.alert_topic_arn != null
    error_message = "alert_topic_arn is required when enable_deletion_alerts is true."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

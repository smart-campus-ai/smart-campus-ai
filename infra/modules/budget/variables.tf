variable "name_prefix" {
  description = "Prefix of every resource name, for example \"sc-dev\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "monthly_limit_usd" {
  description = "Monthly cost limit of the budget, in USD."
  type        = number

  validation {
    condition     = var.monthly_limit_usd > 0
    error_message = "monthly_limit_usd must be strictly greater than 0."
  }
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic (owned by the notifications module) that receives the budget and anomaly alerts. The topic policy must allow budgets.amazonaws.com and costalerts.amazonaws.com to publish: see the topic_policy_statement_json output. Required when enable_anomaly_detection is true."
  type        = string
  default     = null

  validation {
    condition     = var.sns_topic_arn == null || can(regex("^arn:aws(-[a-z]+)*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]{1,256}$", coalesce(var.sns_topic_arn, "invalid")))
    error_message = "sns_topic_arn must be an SNS topic ARN (arn:<partition>:sns:<region>:<account id>:<topic name>)."
  }
}

variable "notification_emails" {
  description = "Email addresses that receive the budget notifications directly (max 10 per notification)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.notification_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Every notification_emails entry must be a valid email address."
  }

  validation {
    condition     = length(var.notification_emails) <= 10
    error_message = "A budget notification accepts at most 10 email addresses."
  }

  validation {
    condition     = var.sns_topic_arn != null || length(var.notification_emails) >= 1
    error_message = "At least one recipient is required: set sns_topic_arn and/or notification_emails."
  }
}

variable "forecasted_thresholds_percent" {
  description = "Percentages of the monthly limit above which a notification is sent on the forecasted cost."
  type        = list(number)
  default     = [80, 100]

  validation {
    condition     = alltrue([for t in var.forecasted_thresholds_percent : t > 0 && t <= 1000])
    error_message = "Every forecasted threshold must be greater than 0 and at most 1000 (percent)."
  }
}

variable "actual_thresholds_percent" {
  description = "Percentages of the monthly limit above which a notification is sent on the actual cost."
  type        = list(number)
  default     = [100]

  validation {
    condition     = alltrue([for t in var.actual_thresholds_percent : t > 0 && t <= 1000])
    error_message = "Every actual threshold must be greater than 0 and at most 1000 (percent)."
  }

  validation {
    condition     = length(var.actual_thresholds_percent) + length(var.forecasted_thresholds_percent) >= 1
    error_message = "At least one forecasted or actual threshold is required."
  }
}

variable "project_tag_value" {
  description = "Value of the cost allocation tag project_tag_key used to filter the budget. When null, the budget covers the whole account. The tag must be activated as a cost allocation tag in the billing console."
  type        = string
  default     = null

  validation {
    condition     = var.project_tag_value == null || can(regex("^[^$]{1,256}$", coalesce(var.project_tag_value, "")))
    error_message = "project_tag_value must be 1 to 256 characters and must not contain \"$\"."
  }
}

variable "project_tag_key" {
  description = "Key of the cost allocation tag used to filter the budget when project_tag_value is set."
  type        = string
  default     = "Project"

  validation {
    condition     = can(regex("^[^$]{1,128}$", var.project_tag_key))
    error_message = "project_tag_key must be 1 to 128 characters and must not contain \"$\"."
  }
}

variable "enable_anomaly_detection" {
  description = "Create a Cost Anomaly Detection monitor (per AWS service) and a subscription that publishes to sns_topic_arn."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_anomaly_detection || var.sns_topic_arn != null
    error_message = "sns_topic_arn is required when enable_anomaly_detection is true."
  }
}

variable "anomaly_threshold_usd" {
  description = "Minimum absolute total impact, in USD, of an anomaly for an alert to be sent."
  type        = number
  default     = 10

  validation {
    condition     = var.anomaly_threshold_usd > 0
    error_message = "anomaly_threshold_usd must be strictly greater than 0."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

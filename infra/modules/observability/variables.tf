variable "name_prefix" {
  description = "Prefix of every resource name, in the form sc-<env> (for example \"sc-dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "alarm_topic_arn" {
  description = "ARN of the SNS topic (\"ops\" topic, EN-45) notified when an alarm goes into the ALARM state. The topic policy must allow cloudwatch.amazonaws.com to publish, scoped by aws:SourceAccount."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]{1,256}$", var.alarm_topic_arn))
    error_message = "alarm_topic_arn must be an SNS topic ARN (arn:<partition>:sns:<region>:<account id>:<topic name>)."
  }
}

# ---------------------------------------------------------------------------
# Observed resources. Names only: the module never discovers resources.
# ---------------------------------------------------------------------------

variable "api" {
  description = "REST API stage to observe (API Gateway ApiName and Stage dimensions). Null disables the API widgets and the API 5xx and latency alarms."
  type = object({
    name       = string
    stage_name = string
  })
  default = null

  validation {
    condition     = var.api == null || can(regex("^[A-Za-z0-9._ -]{1,128}$", var.api.name))
    error_message = "api.name must be 1 to 128 characters: letters, digits, spaces, dots, underscores and hyphens."
  }

  validation {
    condition     = var.api == null || can(regex("^[A-Za-z0-9_-]{1,128}$", var.api.stage_name))
    error_message = "api.stage_name must be 1 to 128 characters: letters, digits, underscores and hyphens."
  }
}

variable "lambda_function_names" {
  description = "Names of the Lambda functions to observe. Each one gets an errors alarm and a throttles alarm."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.lambda_function_names : can(regex("^[A-Za-z0-9_-]{1,64}$", n))])
    error_message = "Every lambda_function_names entry must be 1 to 64 characters: letters, digits, underscores and hyphens (a function name, not an ARN)."
  }
}

variable "dynamodb_table_names" {
  description = "Names of the DynamoDB tables to show on the dashboard (consumed capacity and throttle events). No alarm."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.dynamodb_table_names : can(regex("^[A-Za-z0-9_.-]{3,255}$", n))])
    error_message = "Every dynamodb_table_names entry must be 3 to 255 characters: letters, digits, underscores, dots and hyphens."
  }
}

variable "dlq_queue_names" {
  description = "Names of the SQS dead-letter queues to observe. Each one gets a depth alarm."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.dlq_queue_names : can(regex("^[A-Za-z0-9_-]{1,75}(\\.fifo)?$", n))])
    error_message = "Every dlq_queue_names entry must be a queue name (1 to 80 characters: letters, digits, underscores and hyphens, optional .fifo suffix), not a URL or an ARN."
  }
}

variable "waf_regional_web_acl_names" {
  description = "Names of the REGIONAL web ACLs (API stage) to observe, in the region of the module. Each one gets a blocked-requests alarm."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.waf_regional_web_acl_names : can(regex("^[A-Za-z0-9_-]{1,128}$", n))])
    error_message = "Every waf_regional_web_acl_names entry must be 1 to 128 characters: letters, digits, underscores and hyphens."
  }
}

variable "cloudfront_waf_web_acl_names" {
  description = "Names of the CLOUDFRONT-scope web ACLs to observe. Their metrics live in us-east-1 with the 'Global' region dimension. Each one gets a blocked-requests alarm."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.cloudfront_waf_web_acl_names : can(regex("^[A-Za-z0-9_-]{1,128}$", n))])
    error_message = "Every cloudfront_waf_web_acl_names entry must be 1 to 128 characters: letters, digits, underscores and hyphens."
  }
}

# ---------------------------------------------------------------------------
# Log metric filters. Log groups are owned by the producers (lambda-service,
# API stage, WAF logging): this module only attaches filters to them.
# ---------------------------------------------------------------------------

variable "auth_failure_log_group_name" {
  description = "Name of the API access log group (EN-33) holding JSON access logs. When set, a metric filter counts 401/403 responses, with a dashboard widget and an alarm. Null disables it."
  type        = string
  default     = null

  validation {
    condition     = var.auth_failure_log_group_name == null || can(regex("^[A-Za-z0-9._/#-]{1,512}$", coalesce(var.auth_failure_log_group_name, "!")))
    error_message = "auth_failure_log_group_name must be a CloudWatch log group name (1 to 512 characters: letters, digits, dots, underscores, hyphens, slashes and #)."
  }
}

variable "auth_failure_filter_pattern" {
  description = "CloudWatch Logs filter pattern counting authentication failures in the access log group. The default matches a JSON access log with a numeric status field; align it with the access log format defined by EN-33."
  type        = string
  default     = "{ ($.status = 401) || ($.status = 403) }"

  validation {
    condition     = length(var.auth_failure_filter_pattern) >= 1 && length(var.auth_failure_filter_pattern) <= 1024
    error_message = "auth_failure_filter_pattern must be 1 to 1024 characters."
  }
}

variable "log_metric_filters" {
  description = "Extra metric filters, keyed by a stable name (metric name and alarm suffix). Each filter counts matching events (value 1, no extracted field, so no log content reaches metrics). An alarm is created when alarm_threshold is set: it fires when the count over alarm_period_seconds reaches the threshold."
  type = map(object({
    log_group_name  = string
    pattern         = string
    alarm_threshold = optional(number)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.log_metric_filters) : can(regex("^[a-z][a-z0-9-]{0,40}$", k))])
    error_message = "log_metric_filters keys must be 1 to 41 characters: lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition     = !contains(keys(var.log_metric_filters), "auth-failures")
    error_message = "The log_metric_filters key \"auth-failures\" is reserved for auth_failure_log_group_name."
  }

  validation {
    condition     = alltrue([for f in values(var.log_metric_filters) : can(regex("^[A-Za-z0-9._/#-]{1,512}$", f.log_group_name))])
    error_message = "Every log_metric_filters log_group_name must be a CloudWatch log group name (1 to 512 characters: letters, digits, dots, underscores, hyphens, slashes and #)."
  }

  validation {
    condition     = alltrue([for f in values(var.log_metric_filters) : length(f.pattern) >= 1 && length(f.pattern) <= 1024])
    error_message = "Every log_metric_filters pattern must be 1 to 1024 characters."
  }

  validation {
    condition     = alltrue([for f in values(var.log_metric_filters) : f.alarm_threshold == null || coalesce(f.alarm_threshold, 0) >= 1])
    error_message = "Every log_metric_filters alarm_threshold must be null or greater than or equal to 1."
  }
}

# ---------------------------------------------------------------------------
# Thresholds. Same defaults in every environment; tfvars override per env.
# ---------------------------------------------------------------------------

variable "alarm_period_seconds" {
  description = "Evaluation period of every alarm, in seconds. A multiple of 60; keep 300 or more for SQS and DynamoDB metrics, which are published every 5 minutes."
  type        = number
  default     = 300

  validation {
    condition     = var.alarm_period_seconds >= 60 && var.alarm_period_seconds <= 86400 && var.alarm_period_seconds % 60 == 0
    error_message = "alarm_period_seconds must be a multiple of 60 between 60 and 86400."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods evaluated by the rate-based alarms (API 5xx rate, API latency p95, WAF blocks, log metric filters). Errors, throttles and DLQ depth alarms always evaluate one period."
  type        = number
  default     = 3

  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 24 && floor(var.alarm_evaluation_periods) == var.alarm_evaluation_periods
    error_message = "alarm_evaluation_periods must be a whole number between 1 and 24."
  }
}

variable "alarm_datapoints_to_alarm" {
  description = "Number of breaching periods, out of alarm_evaluation_periods, that put a rate-based alarm into ALARM."
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_datapoints_to_alarm >= 1 && floor(var.alarm_datapoints_to_alarm) == var.alarm_datapoints_to_alarm
    error_message = "alarm_datapoints_to_alarm must be a whole number greater than or equal to 1."
  }

  validation {
    condition     = var.alarm_datapoints_to_alarm <= var.alarm_evaluation_periods
    error_message = "alarm_datapoints_to_alarm must be less than or equal to alarm_evaluation_periods."
  }
}

variable "api_5xx_rate_threshold_percent" {
  description = "API 5xx rate (percent of requests) above which the 5xx alarm fires."
  type        = number
  default     = 1

  validation {
    condition     = var.api_5xx_rate_threshold_percent > 0 && var.api_5xx_rate_threshold_percent <= 100
    error_message = "api_5xx_rate_threshold_percent must be greater than 0 and at most 100."
  }
}

variable "api_5xx_min_requests" {
  description = "Minimum number of requests in a period for the 5xx rate to be evaluated; below it the rate is treated as 0 so that a single error on a quiet API does not page."
  type        = number
  default     = 10

  validation {
    condition     = var.api_5xx_min_requests >= 1 && floor(var.api_5xx_min_requests) == var.api_5xx_min_requests
    error_message = "api_5xx_min_requests must be a whole number greater than or equal to 1."
  }
}

variable "api_latency_p95_threshold_ms" {
  description = "API p95 latency, in milliseconds, above which the latency alarm fires (NFR: 2000)."
  type        = number
  default     = 2000

  validation {
    condition     = var.api_latency_p95_threshold_ms > 0
    error_message = "api_latency_p95_threshold_ms must be greater than 0."
  }
}

variable "lambda_errors_threshold" {
  description = "Number of errors per period above which a Lambda errors alarm fires."
  type        = number
  default     = 0

  validation {
    condition     = var.lambda_errors_threshold >= 0
    error_message = "lambda_errors_threshold must be greater than or equal to 0."
  }
}

variable "lambda_throttles_threshold" {
  description = "Number of throttles per period above which a Lambda throttles alarm fires."
  type        = number
  default     = 0

  validation {
    condition     = var.lambda_throttles_threshold >= 0
    error_message = "lambda_throttles_threshold must be greater than or equal to 0."
  }
}

variable "dlq_depth_threshold" {
  description = "Number of visible messages above which a DLQ depth alarm fires. 0 means any message."
  type        = number
  default     = 0

  validation {
    condition     = var.dlq_depth_threshold >= 0
    error_message = "dlq_depth_threshold must be greater than or equal to 0."
  }
}

variable "waf_blocked_requests_threshold" {
  description = "Number of requests blocked by a regional web ACL per period above which the WAF alarm fires (spike detection)."
  type        = number
  default     = 100

  validation {
    condition     = var.waf_blocked_requests_threshold >= 1
    error_message = "waf_blocked_requests_threshold must be greater than or equal to 1."
  }
}

variable "auth_failure_threshold" {
  description = "Number of 401/403 responses per period at or above which the authentication failure alarm fires (spike detection)."
  type        = number
  default     = 50

  validation {
    condition     = var.auth_failure_threshold >= 1
    error_message = "auth_failure_threshold must be greater than or equal to 1."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

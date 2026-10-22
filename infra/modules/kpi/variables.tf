variable "name_prefix" {
  description = "Prefix of every resource name, in the form sc-<env> (for example \"sc-dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "kms_key_arn" {
  description = "ARN of the customer-managed KMS key (\"data\" domain, EN-14) that encrypts the kpi table and the failure queue, and that protects the tickets stream. The key policy must allow DynamoDB and SQS to use it."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]{36}$", var.kms_key_arn))
    error_message = "kms_key_arn must be the ARN of a KMS key (arn:<partition>:kms:<region>:<account id>:key/<key id>), not an alias."
  }
}

variable "enable_deletion_protection" {
  description = "Protect the kpi table against deletion. Must be true in prod; no default so that each environment decides explicitly."
  type        = bool
}

variable "stream_arn" {
  description = "ARN of the tickets table stream (output stream_arn of tickets-store, NEW_AND_OLD_IMAGES)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:dynamodb:[a-z0-9-]+:[0-9]{12}:table/[A-Za-z0-9_.-]{3,255}/stream/[0-9T:.-]+$", var.stream_arn))
    error_message = "stream_arn must be a DynamoDB stream ARN (arn:<partition>:dynamodb:<region>:<account id>:table/<name>/stream/<label>)."
  }
}

variable "function_name" {
  description = "Name or ARN of the kpi-aggregator Lambda function, qualified with the :live alias (for example \"sc-dev-kpi-aggregator:live\" or the alias ARN) so that the mapping targets the live alias."
  type        = string

  validation {
    condition     = can(regex("^(arn:aws(-[a-z]+)*:lambda:[a-z0-9-]+:[0-9]{12}:function:)?[A-Za-z0-9_-]{1,64}:live$", var.function_name))
    error_message = "function_name must be a Lambda function name or ARN followed by :live alias (the mapping must target the live alias)."
  }
}

variable "partition_key_name" {
  description = "Name of the partition key attribute (string) of the kpi table, for example the aggregate day. Aligned with SE in packages/contracts."
  type        = string
  default     = "pk"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,63}$", var.partition_key_name))
    error_message = "partition_key_name must start with a letter and contain only letters, digits and underscores (64 characters max)."
  }
}

variable "sort_key_name" {
  description = "Name of the sort key attribute (string) of the kpi table, for example the aggregate dimension (status, category)."
  type        = string
  default     = "sk"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,63}$", var.sort_key_name))
    error_message = "sort_key_name must start with a letter and contain only letters, digits and underscores (64 characters max)."
  }

  validation {
    condition     = var.sort_key_name != var.partition_key_name
    error_message = "sort_key_name must differ from partition_key_name."
  }
}

variable "ticket_sort_key_name" {
  description = "Name of the sort key attribute of the tickets table, used by the event filter to keep ticket items only."
  type        = string
  default     = "sk"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,63}$", var.ticket_sort_key_name))
    error_message = "ticket_sort_key_name must start with a letter and contain only letters, digits and underscores (64 characters max)."
  }
}

variable "ticket_meta_sort_key_value" {
  description = "Sort key value of the ticket item itself in the tickets table (the audit trail items use another value)."
  type        = string
  default     = "META"

  validation {
    condition     = length(var.ticket_meta_sort_key_value) > 0 && length(var.ticket_meta_sort_key_value) <= 128
    error_message = "ticket_meta_sort_key_value must be 1 to 128 characters."
  }
}

variable "ticket_status_attribute_name" {
  description = "Name of the status attribute of the ticket item, used by the event filter."
  type        = string
  default     = "status"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,63}$", var.ticket_status_attribute_name))
    error_message = "ticket_status_attribute_name must start with a letter and contain only letters, digits and underscores (64 characters max)."
  }
}

variable "starting_position" {
  description = "Where the mapping starts reading the stream: TRIM_HORIZON (oldest available record, no event lost) or LATEST."
  type        = string
  default     = "TRIM_HORIZON"

  validation {
    condition     = contains(["TRIM_HORIZON", "LATEST"], var.starting_position)
    error_message = "starting_position must be TRIM_HORIZON or LATEST."
  }
}

variable "batch_size" {
  description = "Maximum number of stream records sent to one invocation."
  type        = number
  default     = 100

  validation {
    condition     = var.batch_size >= 1 && var.batch_size <= 10000 && floor(var.batch_size) == var.batch_size
    error_message = "batch_size must be an integer between 1 and 10000."
  }
}

variable "maximum_batching_window_in_seconds" {
  description = "Maximum time in seconds to gather records before invoking the function."
  type        = number
  default     = 5

  validation {
    condition     = var.maximum_batching_window_in_seconds >= 0 && var.maximum_batching_window_in_seconds <= 300 && floor(var.maximum_batching_window_in_seconds) == var.maximum_batching_window_in_seconds
    error_message = "maximum_batching_window_in_seconds must be an integer between 0 and 300."
  }
}

variable "maximum_retry_attempts" {
  description = "Number of retries of a failing batch before it is sent to the failure queue. Bounded so that a poison record cannot block a shard."
  type        = number
  default     = 3

  validation {
    condition     = var.maximum_retry_attempts >= 0 && var.maximum_retry_attempts <= 10000 && floor(var.maximum_retry_attempts) == var.maximum_retry_attempts
    error_message = "maximum_retry_attempts must be an integer between 0 and 10000 (-1, infinite retries, is refused: the failure destination would never be used)."
  }
}

variable "maximum_record_age_in_seconds" {
  description = "Maximum age in seconds of a record the mapping still processes; older records go to the failure queue. Bounded for the same reason as the retries."
  type        = number
  default     = 86400

  validation {
    condition     = var.maximum_record_age_in_seconds >= 60 && var.maximum_record_age_in_seconds <= 604800 && floor(var.maximum_record_age_in_seconds) == var.maximum_record_age_in_seconds
    error_message = "maximum_record_age_in_seconds must be an integer between 60 and 604800 (-1, no limit, is refused)."
  }
}

variable "dlq_retention_seconds" {
  description = "Retention in seconds of the messages in the failure queue (60 s to 14 days)."
  type        = number
  default     = 1209600

  validation {
    condition     = var.dlq_retention_seconds >= 60 && var.dlq_retention_seconds <= 1209600 && floor(var.dlq_retention_seconds) == var.dlq_retention_seconds
    error_message = "dlq_retention_seconds must be an integer between 60 and 1209600."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

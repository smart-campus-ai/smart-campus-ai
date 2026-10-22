variable "name_prefix" {
  description = "Prefix of every resource name, in the form sc-<env> (for example \"sc-dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "function_name" {
  description = "Short name of the function (for example \"tickets\"). The deployed function is named <name_prefix>-<function_name>."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,28}[a-z0-9]$", var.function_name))
    error_message = "function_name must be 2 to 30 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "description" {
  description = "Description of the function."
  type        = string
  default     = null
}

variable "runtime" {
  description = "Lambda runtime identifier (for example \"python3.13\" or \"nodejs24.x\"). Chosen by the application team."
  type        = string

  validation {
    condition     = can(regex("^(nodejs|python|java|dotnet|ruby|provided)[a-z0-9.]*$", var.runtime))
    error_message = "runtime must be a Lambda runtime identifier such as python3.13, nodejs24.x, java21 or provided.al2023."
  }
}

variable "handler" {
  description = "Function entrypoint in the deployed code (for example \"app.handler\"). Chosen by the application team."
  type        = string

  validation {
    condition     = can(regex("^[^\\s]{1,128}$", var.handler))
    error_message = "handler must be 1 to 128 characters without whitespace."
  }
}

variable "memory_size" {
  description = "Memory of the function, in MB."
  type        = number
  default     = 256

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240 && floor(var.memory_size) == var.memory_size
    error_message = "memory_size must be a whole number between 128 and 10240."
  }
}

variable "timeout" {
  description = "Timeout of the function, in seconds."
  type        = number
  default     = 10

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900 && floor(var.timeout) == var.timeout
    error_message = "timeout must be a whole number between 1 and 900."
  }
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrency of the function. -1 leaves the function unreserved; 0 throttles every invocation. Reserving concurrency is only possible while the account keeps at least 10 unreserved executions."
  type        = number
  default     = -1

  validation {
    condition     = var.reserved_concurrent_executions >= -1 && floor(var.reserved_concurrent_executions) == var.reserved_concurrent_executions
    error_message = "reserved_concurrent_executions must be a whole number greater than or equal to -1."
  }
}

variable "environment_variables" {
  description = "Plain environment variables of the function. Never put a secret here: pass the name of the SSM parameter or Secrets Manager secret (key suffixed with _SSM_PARAMETER or _SECRET_ARN) and read it at runtime."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key in keys(var.environment_variables) :
      can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", key))
    ])
    error_message = "Environment variable names must start with a letter and contain only letters, digits and underscores."
  }

  validation {
    condition = alltrue([
      for key in keys(var.environment_variables) :
      !can(regex("(?i)(secret|password|passwd|token|api_?key|private_?key|credential)", key)) || can(regex("(_SSM_PARAMETER|_SECRET_ARN)$", key))
    ])
    error_message = "Environment variable names that look like a secret (secret, password, token, api key, private key, credential) must end with _SSM_PARAMETER or _SECRET_ARN and hold a reference, never the value."
  }
}

variable "environment_kms_key_arn" {
  description = "ARN of the customer-managed KMS key (domain data) that encrypts the environment variables. Required: the AWS-managed key is not accepted. The execution role is granted kms:Decrypt on it, only for this function."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", var.environment_kms_key_arn))
    error_message = "environment_kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account id>:key/<id>), not an alias."
  }
}

variable "logs_kms_key_arn" {
  description = "ARN of the customer-managed KMS key (domain logs) that encrypts the log group. Its key policy must allow the CloudWatch Logs service."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", var.logs_kms_key_arn))
    error_message = "logs_kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account id>:key/<id>), not an alias."
  }
}

variable "log_retention_in_days" {
  description = "Retention of the function log group, in days (dev 14, prod 90). A retention of 0 (never expire) is refused."
  type        = number

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of the values accepted by CloudWatch Logs (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}

variable "permissions_boundary_arn" {
  description = "ARN of the project permissions boundary (EN-13) attached to the execution role. The policy name must contain name_prefix, so a dev function cannot use the prod boundary (per-environment boundaries, single account)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:policy/.+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be an IAM policy ARN (arn:<partition>:iam::<account id>:policy/<name>)."
  }

  validation {
    condition     = !can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:policy/.+$", var.permissions_boundary_arn)) || strcontains(element(split("/", var.permissions_boundary_arn), length(split("/", var.permissions_boundary_arn)) - 1), var.name_prefix)
    error_message = "The permissions boundary policy name must contain name_prefix (for example sc-dev-boundary for name_prefix sc-dev)."
  }
}

variable "extra_policy_json" {
  description = "Additional IAM policy document (JSON) merged into the execution role policy: the data access of the function (tables, buckets, parameters, keys). Refused: NotAction and NotResource, Allow statements with Resource \"*\", with a wildcard service (\"*\", \"*:*\"), with iam:*, sts:*, kms:*, iam:PassRole, lambda:Update*, or with lambda wildcards on functions (lambda:*, lambda:*Function*). Scope every resource."
  type        = string
  default     = null

  validation {
    condition     = var.extra_policy_json == null ? true : can(jsondecode(var.extra_policy_json).Statement)
    error_message = "extra_policy_json must be a JSON IAM policy document with a Statement element."
  }

  validation {
    condition = var.extra_policy_json == null ? true : alltrue([
      for statement in flatten([try(jsondecode(var.extra_policy_json).Statement, [])]) :
      try(statement.Effect, "Allow") != "Allow" || alltrue([
        for action in flatten([try(statement.Action, [])]) :
        !can(regex("^([^:]*\\*|(iam|sts|kms):\\*$|iam:passrole$|lambda:(\\*|update)|lambda:.*(\\*.*function|function.*\\*))", lower(action)))
      ])
    ])
    error_message = "extra_policy_json must not allow Action \"*\", a wildcard service, iam:*, sts:*, kms:*, iam:PassRole, lambda:Update* or lambda wildcards (lambda:*, lambda:*Function*)."
  }

  validation {
    condition = var.extra_policy_json == null ? true : alltrue([
      for statement in flatten([try(jsondecode(var.extra_policy_json).Statement, [])]) :
      try(statement.Effect, "Allow") != "Allow" || !contains(flatten([try(statement.Resource, [])]), "*")
    ])
    error_message = "extra_policy_json must not contain an Allow statement with Resource \"*\"; scope every resource."
  }

  validation {
    condition = var.extra_policy_json == null ? true : alltrue([
      for statement in flatten([try(jsondecode(var.extra_policy_json).Statement, [])]) :
      !can(statement.NotAction) && !can(statement.NotResource)
    ])
    error_message = "extra_policy_json must not use NotAction or NotResource."
  }
}

variable "enable_dlq" {
  description = "Create an SQS dead-letter queue (encrypted with dlq_kms_key_arn) that receives the failed asynchronous invocations."
  type        = bool
  default     = false
}

variable "dlq_kms_key_arn" {
  description = "ARN of the customer-managed KMS key that encrypts the dead-letter queue. Required when enable_dlq is true. The execution role is granted kms:GenerateDataKey and kms:Decrypt on it."
  type        = string
  default     = null

  validation {
    condition     = var.dlq_kms_key_arn == null ? true : can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", var.dlq_kms_key_arn))
    error_message = "dlq_kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account id>:key/<id>), not an alias."
  }

  validation {
    condition     = !var.enable_dlq || var.dlq_kms_key_arn != null
    error_message = "dlq_kms_key_arn is required when enable_dlq is true."
  }
}

variable "dlq_message_retention_seconds" {
  description = "Retention of the messages of the dead-letter queue, in seconds (maximum 14 days)."
  type        = number
  default     = 1209600

  validation {
    condition     = var.dlq_message_retention_seconds >= 60 && var.dlq_message_retention_seconds <= 1209600 && floor(var.dlq_message_retention_seconds) == var.dlq_message_retention_seconds
    error_message = "dlq_message_retention_seconds must be a whole number between 60 and 1209600."
  }
}

variable "on_failure_destination_arn" {
  description = "ARN of an SQS queue, SNS topic, EventBridge bus or Lambda function that receives the failed asynchronous invocations of the live alias. The execution role is granted the matching send action; if the destination is encrypted with a customer-managed key, grant that key through extra_policy_json."
  type        = string
  default     = null

  validation {
    condition     = var.on_failure_destination_arn == null ? true : can(regex("^arn:aws(-[a-z]+)*:(sqs|sns|events|lambda):[a-z0-9-]+:[0-9]{12}:.+$", var.on_failure_destination_arn))
    error_message = "on_failure_destination_arn must be the ARN of an SQS queue, SNS topic, EventBridge bus or Lambda function in the account."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

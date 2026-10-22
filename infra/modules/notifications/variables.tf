variable "name_prefix" {
  description = "Prefix of every resource name, in the form sc-<env> (for example \"sc-dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "kms_key_arn" {
  description = "ARN of the customer-managed KMS key (EN-14) that encrypts both SNS topics. Its key policy must let the publishing services (CloudWatch, Budgets, SES) call kms:Decrypt and kms:GenerateDataKey*."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]{36}$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account id>:key/<key id>), not an alias."
  }
}

variable "sender_email_address" {
  description = "Sender e-mail address of the SES identity (AC1: sender addresses or a domain). Optional when sender_domain is set. PII: sensitive; provide it through a tfvars file kept out of the public repository, it is never hardcoded in the module."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.sender_email_address == null || can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", var.sender_email_address))
    error_message = "sender_email_address must be a valid e-mail address."
  }
}

variable "sender_domain" {
  description = "Domain to verify as an SES sender identity (DKIM), for example \"mail.example.org\". Optional when sender_email_address is set. Not the application domain (ADR-0003): it only identifies the mail sender. At least one of sender_email_address and sender_domain is required."
  type        = string
  default     = null

  validation {
    condition     = var.sender_domain == null || can(regex("(?i)^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", var.sender_domain))
    error_message = "sender_domain must be a valid domain name such as mail.example.org."
  }

  validation {
    condition     = var.sender_domain != null || nonsensitive(var.sender_email_address != null)
    error_message = "At least one sender identity is required: set sender_email_address and/or sender_domain."
  }
}

variable "sender_local_parts" {
  description = "Local parts (before the @) the notifier may use as From address on sender_domain, for example [\"noreply\"]. Each one becomes an exact ses:FromAddress value (<local part>@<sender_domain>); no wildcard is ever emitted. Required when sender_domain is set, ignored otherwise."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for lp in var.sender_local_parts : can(regex("^[A-Za-z0-9._%+-]+$", lp))])
    error_message = "Every sender_local_parts entry must be a plain e-mail local part (letters, digits and . _ % + -), without wildcard or @."
  }

  validation {
    condition     = var.sender_domain == null || length(var.sender_local_parts) >= 1
    error_message = "sender_local_parts must list at least one local part when sender_domain is set."
  }
}

variable "recipient_email_identities" {
  description = "Extra e-mail addresses to verify as SES identities. Needed while the account is in the SES sandbox, where every recipient must be a verified identity. Each owner must click the verification link sent by SES. PII: sensitive."
  type        = list(string)
  default     = []
  sensitive   = true

  validation {
    condition     = alltrue([for e in var.recipient_email_identities : can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", e))])
    error_message = "Every recipient_email_identities entry must be a valid e-mail address."
  }
}

variable "admins_email_endpoints" {
  description = "E-mail addresses subscribed to the admins topic (security tickets, SLA escalation). Optional. PII: sensitive. Each subscription must be confirmed manually by its owner, outside OpenTofu."
  type        = list(string)
  default     = []
  sensitive   = true

  validation {
    condition     = alltrue([for e in var.admins_email_endpoints : can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", e))])
    error_message = "Every admins_email_endpoints entry must be a valid e-mail address."
  }
}

variable "ops_email_endpoints" {
  description = "E-mail addresses subscribed to the ops topic (alarms, budgets, SES events). Optional. PII: sensitive. Each subscription must be confirmed manually by its owner, outside OpenTofu."
  type        = list(string)
  default     = []
  sensitive   = true

  validation {
    condition     = alltrue([for e in var.ops_email_endpoints : can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", e))])
    error_message = "Every ops_email_endpoints entry must be a valid e-mail address."
  }
}

variable "admins_publishers" {
  description = "Who may publish to the admins topic. principal_arns: IAM role ARNs (for example the tickets and escalation roles). services: map of AWS service principal to the aws:SourceArn patterns it may publish from (at least one, so a service is never allowed without a SourceArn condition); aws:SourceAccount is added automatically."
  type = object({
    principal_arns = optional(list(string), [])
    services       = optional(map(list(string)), {})
  })
  default = {}

  validation {
    condition     = alltrue([for arn in var.admins_publishers.principal_arns : can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:role/[^*?]+$", arn))])
    error_message = "Every admins_publishers.principal_arns entry must be an IAM role ARN without wildcards."
  }

  validation {
    condition     = alltrue([for service in keys(var.admins_publishers.services) : can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)*\\.amazonaws\\.com$", service))])
    error_message = "Every admins_publishers.services key must be an AWS service principal such as cloudwatch.amazonaws.com."
  }

  validation {
    condition = alltrue([
      for patterns in values(var.admins_publishers.services) :
      length(patterns) >= 1 && alltrue([for p in patterns : can(regex("^arn:aws[-a-z]*:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:.+$", p))])
    ])
    error_message = "Every admins_publishers.services value must list at least one aws:SourceArn pattern with a literal service, region (empty for global services such as budgets), 12-digit account and a resource segment (a bare \"*\" or \"arn:aws:cloudwatch:*\" is refused)."
  }
}

variable "ops_publishers" {
  description = "Who may publish to the ops topic. Same shape as admins_publishers. Typically cloudwatch.amazonaws.com (alarm ARNs of the environment) and budgets.amazonaws.com (budget ARNs). SES is added automatically for the configuration set when enable_configuration_set is true."
  type = object({
    principal_arns = optional(list(string), [])
    services       = optional(map(list(string)), {})
  })
  default = {}

  validation {
    condition     = alltrue([for arn in var.ops_publishers.principal_arns : can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:role/[^*?]+$", arn))])
    error_message = "Every ops_publishers.principal_arns entry must be an IAM role ARN without wildcards."
  }

  validation {
    condition     = alltrue([for service in keys(var.ops_publishers.services) : can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)*\\.amazonaws\\.com$", service))])
    error_message = "Every ops_publishers.services key must be an AWS service principal such as cloudwatch.amazonaws.com."
  }

  validation {
    condition = alltrue([
      for patterns in values(var.ops_publishers.services) :
      length(patterns) >= 1 && alltrue([for p in patterns : can(regex("^arn:aws[-a-z]*:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:.+$", p))])
    ])
    error_message = "Every ops_publishers.services value must list at least one aws:SourceArn pattern with a literal service, region (empty for global services such as budgets), 12-digit account and a resource segment (a bare \"*\" or \"arn:aws:cloudwatch:*\" is refused)."
  }
}

variable "enable_configuration_set" {
  description = "Create an SES configuration set (default for the sender identity, TLS required, reputation metrics) whose bounce, complaint and reject events are published to the ops topic."
  type        = bool
  default     = false
}

variable "enable_configuration_set_grant" {
  description = "Also grant ses:SendEmail on the configuration set ARN (exact ARN, no wildcard) in the send policy. Enable it only if SES evaluates IAM on the default configuration set and sends are denied without it. Requires enable_configuration_set."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_configuration_set_grant || var.enable_configuration_set
    error_message = "enable_configuration_set_grant requires enable_configuration_set = true."
  }
}

variable "configuration_set_event_types" {
  description = "SES event types published to the ops topic when enable_configuration_set is true. Events carry recipient addresses: keep the list to delivery problems."
  type        = list(string)
  default     = ["BOUNCE", "COMPLAINT", "REJECT", "RENDERING_FAILURE"]

  validation {
    condition     = length(var.configuration_set_event_types) >= 1
    error_message = "configuration_set_event_types must contain at least one event type."
  }

  validation {
    condition = alltrue([
      for t in var.configuration_set_event_types :
      contains(["SEND", "REJECT", "BOUNCE", "COMPLAINT", "DELIVERY", "OPEN", "CLICK", "RENDERING_FAILURE", "DELIVERY_DELAY", "SUBSCRIPTION"], t)
    ])
    error_message = "configuration_set_event_types entries must be valid SES event types (SEND, REJECT, BOUNCE, COMPLAINT, DELIVERY, OPEN, CLICK, RENDERING_FAILURE, DELIVERY_DELAY, SUBSCRIPTION)."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

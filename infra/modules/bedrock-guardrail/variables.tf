variable "name_prefix" {
  description = "Prefix of every resource name, in the form sc-<env> (for example \"sc-dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Environment name (for example \"dev\" or \"prod\"), applied as the Environment tag."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.environment))
    error_message = "environment must be 3 to 20 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "kms_key_arn" {
  description = "ARN of the customer-managed KMS key (\"ai\" domain, EN-14) that encrypts the guardrail. The key policy must allow the principal applying the module and the Bedrock service to use it."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]{36}$", var.kms_key_arn))
    error_message = "kms_key_arn must be the ARN of a KMS key (arn:<partition>:kms:<region>:<account id>:key/<key id>), not an alias."
  }
}

variable "denied_topics" {
  description = "Topics the assistant must refuse, keyed by topic name (letters, digits, spaces and _ - ! ? . only, 100 characters max). Each topic has a definition (200 characters max) and up to 5 example phrases (100 characters max each). At least one topic is required."
  type = map(object({
    definition = string
    examples   = optional(list(string), [])
  }))

  validation {
    condition     = length(var.denied_topics) >= 1
    error_message = "denied_topics must declare at least one topic."
  }

  validation {
    condition     = alltrue([for name in keys(var.denied_topics) : can(regex("^[0-9A-Za-z_ !?.-]{1,100}$", name))])
    error_message = "Every denied topic name must be 1 to 100 characters: letters, digits, spaces and _ - ! ? . only."
  }

  validation {
    condition     = alltrue([for t in values(var.denied_topics) : length(t.definition) >= 1 && length(t.definition) <= 200])
    error_message = "Every denied topic definition must be 1 to 200 characters."
  }

  validation {
    condition     = alltrue([for t in values(var.denied_topics) : length(t.examples) <= 5 && alltrue([for e in t.examples : length(e) >= 1 && length(e) <= 100])])
    error_message = "Every denied topic accepts at most 5 examples of 1 to 100 characters each."
  }
}

variable "content_filter_strength" {
  description = "Strength of the HATE, INSULTS, SEXUAL, VIOLENCE and MISCONDUCT filters, applied to prompts and answers. The PROMPT_ATTACK filter is always HIGH on inputs."
  type        = string
  default     = "HIGH"

  validation {
    condition     = contains(["LOW", "MEDIUM", "HIGH"], var.content_filter_strength)
    error_message = "content_filter_strength must be LOW, MEDIUM or HIGH."
  }
}

variable "pii_entities_anonymize" {
  description = "PII types replaced by a placeholder (ANONYMIZE) in prompts and answers. Together with pii_entities_block it must cover at least EMAIL, PHONE and NAME (EN-52-AC2)."
  type        = set(string)
  default     = ["NAME", "EMAIL", "PHONE", "ADDRESS", "AGE", "USERNAME", "IP_ADDRESS"]

  validation {
    condition = alltrue([
      for t in var.pii_entities_anonymize : contains([
        "ADDRESS", "AGE", "NAME", "EMAIL", "PHONE", "USERNAME", "PASSWORD", "DRIVER_ID", "LICENSE_PLATE",
        "VEHICLE_IDENTIFICATION_NUMBER", "CREDIT_DEBIT_CARD_CVV", "CREDIT_DEBIT_CARD_EXPIRY",
        "CREDIT_DEBIT_CARD_NUMBER", "PIN", "INTERNATIONAL_BANK_ACCOUNT_NUMBER", "SWIFT_CODE", "IP_ADDRESS",
        "MAC_ADDRESS", "URL", "AWS_ACCESS_KEY", "AWS_SECRET_KEY",
      ], t)
    ])
    error_message = "pii_entities_anonymize contains a PII type that Bedrock does not support."
  }
}

variable "pii_entities_block" {
  description = "PII types for which the whole prompt or answer is blocked (BLOCK). Must not overlap with pii_entities_anonymize (checked by a precondition on the guardrail, not a variable validation, to avoid a validation cycle)."
  type        = set(string)
  default = [
    "CREDIT_DEBIT_CARD_NUMBER", "CREDIT_DEBIT_CARD_CVV", "CREDIT_DEBIT_CARD_EXPIRY", "PASSWORD", "PIN",
    "INTERNATIONAL_BANK_ACCOUNT_NUMBER", "AWS_ACCESS_KEY", "AWS_SECRET_KEY",
  ]

  validation {
    condition = alltrue([
      for t in var.pii_entities_block : contains([
        "ADDRESS", "AGE", "NAME", "EMAIL", "PHONE", "USERNAME", "PASSWORD", "DRIVER_ID", "LICENSE_PLATE",
        "VEHICLE_IDENTIFICATION_NUMBER", "CREDIT_DEBIT_CARD_CVV", "CREDIT_DEBIT_CARD_EXPIRY",
        "CREDIT_DEBIT_CARD_NUMBER", "PIN", "INTERNATIONAL_BANK_ACCOUNT_NUMBER", "SWIFT_CODE", "IP_ADDRESS",
        "MAC_ADDRESS", "URL", "AWS_ACCESS_KEY", "AWS_SECRET_KEY",
      ], t)
    ])
    error_message = "pii_entities_block contains a PII type that Bedrock does not support."
  }
}

variable "grounding_threshold" {
  description = "Contextual grounding threshold: minimum confidence that an answer is grounded in the retrieved sources. Below it, the answer is blocked (RF03). Between 0 and 0.99, the range accepted by Bedrock."
  type        = number
  default     = 0.75

  validation {
    condition     = var.grounding_threshold >= 0 && var.grounding_threshold <= 0.99
    error_message = "grounding_threshold must be between 0 and 0.99."
  }
}

variable "relevance_threshold" {
  description = "Contextual relevance threshold: minimum confidence that an answer is relevant to the question. Below it, the answer is blocked (RF03). Between 0 and 0.99, the range accepted by Bedrock."
  type        = number
  default     = 0.5

  validation {
    condition     = var.relevance_threshold >= 0 && var.relevance_threshold <= 0.99
    error_message = "relevance_threshold must be between 0 and 0.99."
  }
}

variable "blocked_input_message" {
  description = "Message returned when a prompt is blocked. In French, it says the assistant does not know and offers to create a ticket (EN-52-AC5)."
  type        = string
  default     = "Je ne sais pas répondre à cette demande. Souhaitez-vous créer un ticket pour qu'un agent vous aide ?"

  validation {
    condition     = length(var.blocked_input_message) >= 1 && length(var.blocked_input_message) <= 500
    error_message = "blocked_input_message must be 1 to 500 characters."
  }
}

variable "blocked_output_message" {
  description = "Message returned when an answer is blocked (denied topic, PII, grounding below threshold). In French, it says the assistant does not know and offers to create a ticket (EN-52-AC5)."
  type        = string
  default     = "Je ne sais pas répondre de façon fiable à cette question. Souhaitez-vous créer un ticket pour qu'un agent vous réponde ?"

  validation {
    condition     = length(var.blocked_output_message) >= 1 && length(var.blocked_output_message) <= 500
    error_message = "blocked_output_message must be 1 to 500 characters."
  }
}

variable "tags" {
  description = "Extra tags applied to the guardrail, merged with the provider default_tags. The Environment tag is always set from var.environment."
  type        = map(string)
  default     = {}
}

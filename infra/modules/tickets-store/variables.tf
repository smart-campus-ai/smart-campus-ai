variable "name_prefix" {
  description = "Prefix of every resource name, in the form sc-<env> (for example \"sc-dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "kms_key_arn" {
  description = "ARN of the customer-managed KMS key (\"data\" domain, EN-14) that encrypts the table at rest. The key policy must allow DynamoDB to use it."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]{36}$", var.kms_key_arn))
    error_message = "kms_key_arn must be the ARN of a KMS key (arn:<partition>:kms:<region>:<account id>:key/<key id>), not an alias."
  }
}

variable "enable_deletion_protection" {
  description = "Protect the table against deletion. Must be true in prod; no default so that each environment decides explicitly."
  type        = bool
}

variable "partition_key_name" {
  description = "Name of the partition key attribute (string), shared by every item of a ticket collection (TICKET#<id>). Aligned with SE in packages/contracts."
  type        = string
  default     = "pk"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,63}$", var.partition_key_name))
    error_message = "partition_key_name must start with a letter and contain only letters, digits and underscores (64 characters max)."
  }
}

variable "sort_key_name" {
  description = "Name of the sort key attribute (string): META for the ticket, EVENT#<timestamp> for the audit trail."
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

variable "owner_attribute_name" {
  description = "Name of the attribute holding the owner's Cognito sub (string); partition key of the owner GSI."
  type        = string
  default     = "ownerSub"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,63}$", var.owner_attribute_name))
    error_message = "owner_attribute_name must start with a letter and contain only letters, digits and underscores (64 characters max)."
  }
}

variable "status_attribute_name" {
  description = "Name of the attribute holding the ticket status (string); partition key of the status GSI."
  type        = string
  default     = "status"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,63}$", var.status_attribute_name))
    error_message = "status_attribute_name must start with a letter and contain only letters, digits and underscores (64 characters max)."
  }
}

variable "created_at_attribute_name" {
  description = "Name of the attribute holding the creation date (ISO 8601 string); sort key of both GSIs."
  type        = string
  default     = "createdAt"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,63}$", var.created_at_attribute_name))
    error_message = "created_at_attribute_name must start with a letter and contain only letters, digits and underscores (64 characters max)."
  }
}

variable "ttl_attribute_name" {
  description = "Name of the attribute (epoch seconds) after which DynamoDB expires an item. Null disables TTL."
  type        = string
  default     = null

  validation {
    condition     = var.ttl_attribute_name == null || can(regex("^[A-Za-z][A-Za-z0-9_]{0,63}$", coalesce(var.ttl_attribute_name, "0")))
    error_message = "ttl_attribute_name must be null or start with a letter and contain only letters, digits and underscores (64 characters max)."
  }
}

variable "enable_contributor_insights" {
  description = "Enable CloudWatch Contributor Insights on the table and its indexes to find hot keys. Off by default: it is billed per event."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

variable "name_prefix" {
  description = "Prefix of every resource name, in the form sc-<env> (for example \"sc-dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "kms_key_arn" {
  description = "ARN of the customer-managed KMS key (\"data\" key, EN-14) that encrypts the table at rest. Chat transcripts are personal data, hence the data key shared with tickets. An alias ARN is not accepted by DynamoDB."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account id>:key/<key id>), not an alias."
  }
}

variable "hash_key" {
  description = "Name of the partition key attribute. The default is one item collection per chat session."
  type        = string
  default     = "sessionId"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,254}$", var.hash_key))
    error_message = "hash_key must start with a letter and contain only letters, digits and underscores (255 characters maximum)."
  }
}

variable "hash_key_type" {
  description = "DynamoDB type of the partition key: S (string), N (number) or B (binary)."
  type        = string
  default     = "S"

  validation {
    condition     = contains(["S", "N", "B"], var.hash_key_type)
    error_message = "hash_key_type must be S, N or B."
  }
}

variable "range_key" {
  description = "Name of the sort key attribute, or null for a table with a partition key only. The default orders the messages of a session by timestamp (ISO 8601 string)."
  type        = string
  default     = "ts"

  validation {
    condition     = var.range_key == null || can(regex("^[A-Za-z][A-Za-z0-9_]{0,254}$", coalesce(var.range_key, "invalid")))
    error_message = "range_key must be null or start with a letter and contain only letters, digits and underscores (255 characters maximum)."
  }

  validation {
    condition     = var.range_key == null || var.range_key != var.hash_key
    error_message = "range_key must differ from hash_key."
  }
}

variable "range_key_type" {
  description = "DynamoDB type of the sort key: S (string), N (number) or B (binary). Ignored when range_key is null."
  type        = string
  default     = "S"

  validation {
    condition     = contains(["S", "N", "B"], var.range_key_type)
    error_message = "range_key_type must be S, N or B."
  }
}

variable "enable_owner_index" {
  description = "Create the \"by-owner\" global secondary index, which lists every session of a user (JWT \"sub\") with a Query instead of a Scan (EN-53-AC3). The default keys are keyed by session, so this index is what serves the per-user listing."
  type        = bool
  default     = true
}

variable "owner_index_hash_key" {
  description = "Attribute holding the owner (Cognito \"sub\") of a session; partition key of the \"by-owner\" index. Always a string."
  type        = string
  default     = "sub"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,254}$", var.owner_index_hash_key))
    error_message = "owner_index_hash_key must start with a letter and contain only letters, digits and underscores (255 characters maximum)."
  }

  validation {
    condition     = !var.enable_owner_index || var.owner_index_hash_key != var.owner_index_range_key
    error_message = "owner_index_hash_key must differ from owner_index_range_key."
  }

  validation {
    condition     = !var.enable_owner_index || var.owner_index_hash_key != var.hash_key || var.hash_key_type == "S"
    error_message = "owner_index_hash_key is a string attribute, so it cannot reuse hash_key when hash_key_type is not S."
  }

  validation {
    condition     = !var.enable_owner_index || var.owner_index_hash_key != var.range_key || var.range_key_type == "S"
    error_message = "owner_index_hash_key is a string attribute, so it cannot reuse range_key when range_key_type is not S."
  }
}

variable "owner_index_range_key" {
  description = "Attribute used to sort the sessions of an owner (creation time, ISO 8601 string); sort key of the \"by-owner\" index. Always a string."
  type        = string
  default     = "createdAt"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,254}$", var.owner_index_range_key))
    error_message = "owner_index_range_key must start with a letter and contain only letters, digits and underscores (255 characters maximum)."
  }

  validation {
    condition     = !var.enable_owner_index || var.owner_index_range_key != var.hash_key || var.hash_key_type == "S"
    error_message = "owner_index_range_key is a string attribute, so it cannot reuse hash_key when hash_key_type is not S."
  }

  validation {
    condition     = !var.enable_owner_index || var.owner_index_range_key != var.range_key || var.range_key_type == "S"
    error_message = "owner_index_range_key is a string attribute, so it cannot reuse range_key when range_key_type is not S."
  }
}

variable "ttl_attribute_name" {
  description = "Name of the TTL attribute. Items are purged automatically once the epoch time (in seconds) it holds has passed, which implements the GDPR retention of chat transcripts (US08)."
  type        = string
  default     = "expiresAt"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,254}$", var.ttl_attribute_name))
    error_message = "ttl_attribute_name must start with a letter and contain only letters, digits and underscores (255 characters maximum)."
  }

  validation {
    condition     = var.ttl_attribute_name != var.hash_key && var.ttl_attribute_name != var.range_key
    error_message = "ttl_attribute_name must not be a key attribute of the table."
  }
}

variable "retention_days" {
  description = "Retention of a chat session, in days, applied by the chat service when it sets the TTL attribute on write (expiresAt = last activity + retention_days). The value is still to be validated for GDPR (US08). Exposed as an output so that the service receives it as configuration; the table itself only enforces the TTL attribute."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 365 && floor(var.retention_days) == var.retention_days
    error_message = "retention_days must be a whole number between 1 and 365."
  }
}

variable "deletion_protection_enabled" {
  description = "Protect the table against deletion. Keep it true in prod; set it to false in dev only when the table must be destroyed."
  type        = bool
  default     = true
}

variable "enable_stream" {
  description = "Enable a DynamoDB stream on the table. Off by default: no consumer reads chat sessions, and a stream would copy personal data outside the TTL purge path."
  type        = bool
  default     = false
}

variable "stream_view_type" {
  description = "Content of the stream records. Only used when enable_stream is true."
  type        = string
  default     = "NEW_AND_OLD_IMAGES"

  validation {
    condition     = contains(["KEYS_ONLY", "NEW_IMAGE", "OLD_IMAGE", "NEW_AND_OLD_IMAGES"], var.stream_view_type)
    error_message = "stream_view_type must be KEYS_ONLY, NEW_IMAGE, OLD_IMAGE or NEW_AND_OLD_IMAGES."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

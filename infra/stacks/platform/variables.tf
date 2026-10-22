variable "env" {
  description = "Environment name."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "name_prefix" {
  description = "Prefix of every resource name: sc-<env>."
  type        = string

  validation {
    condition     = var.name_prefix == "sc-${var.env}"
    error_message = "name_prefix must be sc-<env> (for example sc-dev)."
  }
}

variable "aws_region" {
  description = "Default region of the stack."
  type        = string
  default     = "eu-west-3"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like eu-west-3."
  }
}

variable "state_kms_key_arn" {
  description = "ARN of the state KMS key (bootstrap output state_kms_key_arn), used by the OpenTofu state and plan encryption."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]{36}$", var.state_kms_key_arn))
    error_message = "state_kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}

variable "owner" {
  description = "Value of the Owner tag."
  type        = string
  default     = "ops"
}

variable "repository" {
  description = "Value of the Repository tag."
  type        = string
  default     = "smart-campus-ai"
}

variable "data_classification" {
  description = "Value of the DataClassification tag."
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["public", "internal", "confidential"], var.data_classification)
    error_message = "data_classification must be one of public, internal, confidential."
  }
}

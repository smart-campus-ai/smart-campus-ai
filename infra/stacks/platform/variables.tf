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
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like us-east-1."
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

variable "permissions_boundary_arn" {
  description = "ARN of the workload permissions boundary of this environment (bootstrap output workload_boundary_arns, policy sc-<env>-workload-boundary), attached to every IAM role of the stack. Required and not nullable: lambda-service, sla-scheduler and knowledge-base refuse a null boundary, so apply stays blocked until issue #98 (the workshop role cannot set permission boundaries) is resolved. Pass TF_VAR_permissions_boundary_arn."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:policy/.+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be an IAM policy ARN (arn:<partition>:iam::<account id>:policy/<name>)."
  }

  validation {
    condition     = strcontains(var.permissions_boundary_arn, "/${var.name_prefix}-")
    error_message = "permissions_boundary_arn must be the boundary of this environment (policy name starting with name_prefix, for example sc-dev-workload-boundary)."
  }
}

variable "log_retention_in_days" {
  description = "Retention of the Lambda and API Gateway log groups, in days (dev 14, prod 90)."
  type        = number

  validation {
    condition     = var.log_retention_in_days >= 1
    error_message = "log_retention_in_days must be at least 1; a retention of 0 (never expire) is refused."
  }
}

variable "enable_deletion_protection" {
  description = "Protect the DynamoDB tables and the Cognito user pool against deletion. True in prod, false in dev so that the environment can be destroyed."
  type        = bool
}

variable "lambda_runtime" {
  description = "Lambda runtime identifier of the eight functions (for example python3.13). Chosen by the application team (SE); a change is a configuration change, not a code deployment."
  type        = string
}

variable "lambda_handler" {
  description = "Entrypoint of the eight functions in the deployed archive (for example app.handler). Chosen by the application team (SE)."
  type        = string
  default     = "app.handler"
}

variable "api_throttling_rate_limit" {
  description = "Steady-state request rate of the API stage, in requests per second, for every method."
  type        = number
}

variable "api_throttling_burst_limit" {
  description = "Burst capacity of the API stage, in requests, for every method."
  type        = number
}

variable "api_method_throttling" {
  description = "Stricter throttling of sensitive methods, keyed by \"<resource path without leading slash>/<HTTP method>\" (for example chat/POST, tickets/POST)."
  type = map(object({
    rate_limit  = number
    burst_limit = number
  }))
  default = {}
}

variable "local_origins" {
  description = "Extra browser origins used for local development (http://localhost:<port>), added to the Cognito callback and logout URLs and to the CORS origins of the attachments bucket. Empty in prod."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for origin in var.local_origins : can(regex("^http://localhost(:[0-9]{1,5})?$", origin))])
    error_message = "Every local_origins entry must look like http://localhost or http://localhost:5173."
  }
}

variable "spa_callback_path" {
  description = "Path appended to the site URL (and to each local origin) to build the Cognito callback and logout URLs. Must match the redirect URI used by the SPA exactly."
  type        = string
  default     = "/"

  validation {
    condition     = can(regex("^/[^*#?]*$", var.spa_callback_path))
    error_message = "spa_callback_path must start with a slash and contain no wildcard, query string or fragment."
  }
}

variable "cognito_domain_prefix" {
  description = "Prefix of the Cognito hosted domain. Null uses <name_prefix>-auth. It is unique per region across all AWS accounts."
  type        = string
  default     = null
}

variable "chat_retention_days" {
  description = "Retention of a chat session, in days (GDPR, US08). The chat function sets the TTL attribute from it. Value to validate with the PO and the BA."
  type        = number

  validation {
    condition     = var.chat_retention_days >= 1 && floor(var.chat_retention_days) == var.chat_retention_days
    error_message = "chat_retention_days must be a whole number greater than or equal to 1."
  }
}

variable "attachments_retention_days" {
  description = "Retention of the ticket attachments, in days (GDPR), aligned with the ticket retention. Value to validate with the PO and the BA."
  type        = number

  validation {
    condition     = var.attachments_retention_days >= 1 && floor(var.attachments_retention_days) == var.attachments_retention_days
    error_message = "attachments_retention_days must be a whole number greater than or equal to 1."
  }
}

variable "enable_malware_protection" {
  description = "Scan the attachments with GuardDuty Malware Protection for S3 and serve only clean objects. Set to false only where the service is unavailable (EN-11)."
  type        = bool
}

variable "guardrail_denied_topics" {
  description = "Topics the assistant must refuse, keyed by topic name (letters, digits, spaces and _ - ! ? . only). Each topic has a definition (200 characters max) and up to 5 examples (100 characters max each). To be reviewed by the BA."
  type = map(object({
    definition = string
    examples   = optional(list(string), [])
  }))
  default = {
    "Medical or legal advice" = {
      definition = "Requests for a medical diagnosis, a treatment or legal counsel, which the campus assistant must not give."
      examples   = ["Which medicine should I take for my migraine?", "Can I sue my landlord?"]
    }
    "Academic dishonesty" = {
      definition = "Requests to cheat at an exam, to plagiarize or to bypass the academic integrity rules of the school."
      examples   = ["Give me the answers of tomorrow's exam.", "Write my thesis so that nobody notices."]
    }
    "Personal data of other people" = {
      definition = "Requests to reveal personal data, grades or tickets that belong to other students or to staff members."
      examples   = ["Show me the tickets of another student.", "What is the phone number of this teacher?"]
    }
  }
}

variable "enable_knowledge_base" {
  description = "Create the Bedrock knowledge base (S3 Vectors) of the assistant. Off where Bedrock Knowledge Bases or S3 Vectors are not confirmed (EN-11)."
  type        = bool
}

variable "knowledge_base_writer_principal_arns" {
  description = "IAM role or user ARNs that are the only principals allowed to write the knowledge base source documents (the application deploy role). Required when enable_knowledge_base is true."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.enable_knowledge_base || length(var.knowledge_base_writer_principal_arns) >= 1
    error_message = "knowledge_base_writer_principal_arns must contain at least one principal when enable_knowledge_base is true."
  }
}

variable "chat_foundation_model_id" {
  description = "Foundation model ID behind the chat inference profile (for example anthropic.<model>). Required when enable_knowledge_base is true."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_knowledge_base || var.chat_foundation_model_id != null
    error_message = "chat_foundation_model_id is required when enable_knowledge_base is true."
  }
}

variable "chat_inference_profile_id" {
  description = "ID of the cross-region inference profile invoked by the chat function (us.<model> in the workshop, ADR-0013; an EU profile in a real production). Required when enable_knowledge_base is true."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_knowledge_base || var.chat_inference_profile_id != null
    error_message = "chat_inference_profile_id is required when enable_knowledge_base is true."
  }
}

variable "chat_inference_regions" {
  description = "Regions the chat inference profile routes to, one explicit region each (no wildcard). Required when enable_knowledge_base is true."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.enable_knowledge_base || length(var.chat_inference_regions) >= 1
    error_message = "chat_inference_regions must list at least one region when enable_knowledge_base is true."
  }

  validation {
    condition     = alltrue([for region in var.chat_inference_regions : can(regex("^[a-z]{2}-[a-z]+-[0-9]$", region))])
    error_message = "Every chat_inference_regions entry must look like us-east-1."
  }
}

variable "embedding_model_id" {
  description = "Foundation model ID of the knowledge base embeddings (ADR-0013: Titan Text Embeddings v2)."
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "embedding_dimension" {
  description = "Number of dimensions of the embedding vectors (256, 512 or 1024 for Titan Text Embeddings v2). Cannot be changed without recreating the vector index."
  type        = number
  default     = 1024
}

variable "sender_email_address" {
  description = "Sender e-mail address of the SES identity. PII: sensitive, never stored in a tfvars file of the repository; pass TF_VAR_sender_email_address. At least one of sender_email_address and sender_domain is required."
  type        = string
  default     = null
  sensitive   = true
}

variable "sender_domain" {
  description = "Domain verified as an SES sender identity (DKIM). It only identifies the mail sender, not the application (ADR-0003)."
  type        = string
  default     = null
}

variable "sender_local_parts" {
  description = "Local parts the notifier may use as From address on sender_domain. Required when sender_domain is set."
  type        = list(string)
  default     = []
}

variable "recipient_email_identities" {
  description = "E-mail addresses verified as SES identities while the account is in the SES sandbox. PII: sensitive, pass TF_VAR_recipient_email_identities."
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "admins_email_endpoints" {
  description = "E-mail addresses subscribed to the admins SNS topic. PII: sensitive, pass TF_VAR_admins_email_endpoints. Each subscription is confirmed by hand by its owner."
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "ops_email_endpoints" {
  description = "E-mail addresses subscribed to the ops SNS topic. PII: sensitive, pass TF_VAR_ops_email_endpoints. Each subscription is confirmed by hand by its owner."
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "name_prefix" {
  description = "Prefix of every resource name, in the form sc-<env> (for example \"sc-dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "kms_key_arn" {
  description = "ARN of the customer-managed KMS key (\"ai\" domain, EN-14) that encrypts the source bucket, the vector bucket, the vector index and the data transient during ingestion. Its key policy must let the S3 Vectors service and the knowledge base service role use it."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]{36}$", var.kms_key_arn))
    error_message = "kms_key_arn must be the ARN of a KMS key (arn:<partition>:kms:<region>:<account id>:key/<key id>), not an alias."
  }
}

variable "permissions_boundary_arn" {
  description = "ARN of the project permissions boundary policy attached to the knowledge base service role. null attaches no boundary: only for the workshop exception of ADR-0014 (stacks enforce its scope and expiry)."
  type        = string
  nullable    = true

  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:policy/.+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be an IAM policy ARN (arn:<partition>:iam::<account id>:policy/<name>)."
  }
}

variable "writer_principal_arns" {
  description = "IAM role or user ARNs that are the only principals allowed to write or delete objects in the source bucket (for example the application deploy role). Every other principal, including the account administrators, is denied by the bucket policy. The knowledge base service role only reads and needs no entry."
  type        = list(string)

  validation {
    condition     = length(var.writer_principal_arns) >= 1
    error_message = "writer_principal_arns must contain at least one principal."
  }

  validation {
    condition     = alltrue([for arn in var.writer_principal_arns : can(regex("^arn:aws(-[a-z]+)*:iam::[0-9]{12}:(role|user)/[^*?]+$", arn))])
    error_message = "Every writer_principal_arns entry must be an IAM role or user ARN (arn:<partition>:iam::<account id>:role/<name> or user/<name>), without wildcards."
  }
}

variable "source_prefix" {
  description = "Key prefix of the source documents in the bucket. The data source only ingests objects under this prefix, and the service role can only read objects under it."
  type        = string
  default     = "documents/"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9!_.()=-]*(/[A-Za-z0-9!_.()=-]+)*/$", var.source_prefix))
    error_message = "source_prefix must end with a slash and contain only letters, digits and the characters ! _ . ( ) = - (for example \"documents/\")."
  }
}

variable "embedding_model_arn" {
  description = "ARN of the embedding model used to vectorize the documents and the queries: a foundation model (arn:aws:bedrock:<region>::foundation-model/<id>) or a cross-region inference profile (arn:aws:bedrock:<region>:<account id>:inference-profile/<id>), for example an EU profile so that inference stays in the EU."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:bedrock:[a-z0-9-]+:([0-9]{12})?:(foundation-model|inference-profile)/[A-Za-z0-9.:_-]+$", var.embedding_model_arn))
    error_message = "embedding_model_arn must be a Bedrock foundation model ARN (arn:<partition>:bedrock:<region>::foundation-model/<id>) or inference profile ARN (arn:<partition>:bedrock:<region>:<account id>:inference-profile/<id>)."
  }
}

variable "embedding_model_additional_arns" {
  description = "Foundation model ARNs the service role may also invoke. Required when embedding_model_arn is an inference profile: list the underlying foundation model in each region the profile routes to, one explicit ARN per region (no wildcard region). Leave empty when embedding_model_arn is a foundation model."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.embedding_model_additional_arns : can(regex("^arn:aws(-[a-z]+)*:bedrock:[a-z0-9-]+::foundation-model/[A-Za-z0-9.:_-]+$", arn))])
    error_message = "Every embedding_model_additional_arns entry must be a foundation model ARN with an explicit region (arn:<partition>:bedrock:<region>::foundation-model/<id>), without a wildcard region or model."
  }

  validation {
    condition     = !can(regex(":inference-profile/", var.embedding_model_arn)) || length(var.embedding_model_additional_arns) >= 1
    error_message = "embedding_model_additional_arns must list the underlying foundation model of every routing region when embedding_model_arn is an inference profile."
  }
}

variable "inference_profile_arn" {
  description = "ARN of the cross-region inference profile the chat function invokes to generate answers (for example a US system profile in the workshop region). Scoped in policy_json_retrieve."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:bedrock:[a-z0-9-]+:[0-9]{12}:inference-profile/[A-Za-z0-9.:_-]+$", var.inference_profile_arn))
    error_message = "inference_profile_arn must be an inference profile ARN with an explicit region and account (arn:<partition>:bedrock:<region>:<account id>:inference-profile/<id>), without wildcards."
  }
}

variable "inference_model_arns" {
  description = "Foundation model ARNs underlying inference_profile_arn: one explicit ARN for each region the profile routes to (no wildcard region). Bedrock authorizes the invocation on the profile and on each of these models."
  type        = list(string)

  validation {
    condition     = length(var.inference_model_arns) >= 1
    error_message = "inference_model_arns must contain at least one foundation model ARN."
  }

  validation {
    condition     = alltrue([for arn in var.inference_model_arns : can(regex("^arn:aws(-[a-z]+)*:bedrock:[a-z0-9-]+::foundation-model/[A-Za-z0-9.:_-]+$", arn))])
    error_message = "Every inference_model_arns entry must be a foundation model ARN with an explicit region (arn:<partition>:bedrock:<region>::foundation-model/<id>), without a wildcard region or model."
  }
}

variable "ingestion_function_arn" {
  description = "ARN of the Lambda function (kb-sync) invoked on document creation and deletion under source_prefix. Required when enable_ingestion_notification is true; the function is owned by the platform stack. Its environment needs knowledge_base_id and data_source_id, so build this ARN from the function name instead of the function resource to avoid a dependency cycle."
  type        = string
  default     = null

  validation {
    condition     = var.ingestion_function_arn == null || can(regex("^arn:aws(-[a-z]+)*:lambda:[a-z0-9-]+:[0-9]{12}:function:[A-Za-z0-9_-]+(:[A-Za-z0-9_$-]+)?$", var.ingestion_function_arn))
    error_message = "ingestion_function_arn must be a Lambda function ARN, optionally qualified (arn:<partition>:lambda:<region>:<account id>:function:<name>[:<alias>])."
  }

  validation {
    condition     = !var.enable_ingestion_notification || var.ingestion_function_arn != null
    error_message = "ingestion_function_arn is required when enable_ingestion_notification is true."
  }
}

variable "enable_ingestion_notification" {
  description = "Send the S3 object-created and object-removed events under source_prefix to ingestion_function_arn (EN-51 AC4), and allow S3 to invoke it."
  type        = bool
  default     = true
}

variable "vector_dimension" {
  description = "Number of dimensions of the embedding vectors. Must be a size the embedding model produces (for example 256, 512 or 1024 for Titan Text Embeddings V2). Cannot be changed without recreating the index."
  type        = number

  validation {
    condition     = var.vector_dimension >= 1 && var.vector_dimension <= 4096 && floor(var.vector_dimension) == var.vector_dimension
    error_message = "vector_dimension must be a whole number between 1 and 4096 (S3 Vectors limit)."
  }
}

variable "distance_metric" {
  description = "Distance metric of the vector index similarity search. Cannot be changed without recreating the index."
  type        = string
  default     = "cosine"

  validation {
    condition     = contains(["cosine", "euclidean"], var.distance_metric)
    error_message = "distance_metric must be \"cosine\" or \"euclidean\"."
  }
}

variable "enable_embedding_model_configuration" {
  description = "Pass vector_dimension and the FLOAT32 data type to the embedding model. Turn off for models that do not accept a dimension setting (for example Titan Text Embeddings V1, fixed at 1536)."
  type        = bool
  default     = true
}

variable "chunking_max_tokens" {
  description = "Maximum number of tokens in a chunk (fixed-size chunking)."
  type        = number
  default     = 300

  validation {
    condition     = var.chunking_max_tokens >= 20 && var.chunking_max_tokens <= 8192 && floor(var.chunking_max_tokens) == var.chunking_max_tokens
    error_message = "chunking_max_tokens must be a whole number between 20 and 8192."
  }
}

variable "chunking_overlap_percentage" {
  description = "Percentage of tokens shared between two consecutive chunks (fixed-size chunking)."
  type        = number
  default     = 20

  validation {
    condition     = var.chunking_overlap_percentage >= 1 && var.chunking_overlap_percentage <= 99 && floor(var.chunking_overlap_percentage) == var.chunking_overlap_percentage
    error_message = "chunking_overlap_percentage must be a whole number between 1 and 99."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days after which noncurrent versions of the source documents are permanently deleted."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days
    error_message = "noncurrent_version_expiration_days must be a whole number greater than or equal to 1."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Number of days after which an incomplete multipart upload is aborted."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1 && floor(var.abort_incomplete_multipart_upload_days) == var.abort_incomplete_multipart_upload_days
    error_message = "abort_incomplete_multipart_upload_days must be a whole number greater than or equal to 1."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

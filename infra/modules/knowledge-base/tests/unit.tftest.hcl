mock_provider "aws" {
  # Fake documentation account ID and region, used only to keep names and conditions predictable.
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-1"
    }
  }

  # Computed attributes are unknown at plan time; policies and dependent resources consume them.
  override_resource {
    target = aws_s3_bucket.sources
    values = {
      id  = "sc-dev-kb-sources-123456789012"
      arn = "arn:aws:s3:::sc-dev-kb-sources-123456789012"
    }
  }

  override_resource {
    target = aws_s3vectors_vector_bucket.this
    values = {
      vector_bucket_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/sc-dev-kb-vectors"
    }
  }

  override_resource {
    target = aws_s3vectors_index.this
    values = {
      index_arn = "arn:aws:s3vectors:us-east-1:123456789012:bucket/sc-dev-kb-vectors/index/sc-dev-kb-index"
    }
  }

  override_resource {
    target = aws_iam_role.service
    values = {
      id  = "sc-dev-kb-service"
      arn = "arn:aws:iam::123456789012:role/sc-dev-kb-service"
    }
  }

  override_resource {
    target = aws_bedrockagent_knowledge_base.this
    values = {
      id  = "KBTEST0001"
      arn = "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/KBTEST0001"
    }
  }

  # The mock returns random strings for computed attributes, which the bucket policy and role reject as invalid
  # JSON. The invariants are asserted on the document arguments (known at plan), not on the JSON.
  override_data {
    target = data.aws_iam_policy_document.sources_bucket
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.service_trust
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.service
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix              = "sc-dev"
  kms_key_arn              = "arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/sc-dev-boundary"
  writer_principal_arns    = ["arn:aws:iam::123456789012:role/sc-dev-app-deploy"]
  embedding_model_arn      = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
  vector_dimension         = 1024
  inference_profile_arn    = "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.anthropic.claude-sonnet-4-20250514-v1:0"
  inference_model_arns = [
    "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0",
    "arn:aws:bedrock:us-east-2::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0",
    "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0",
  ]
  ingestion_function_arn = "arn:aws:lambda:us-east-1:123456789012:function:sc-dev-kb-sync:live"
}

# EN51-AC1: bucket blocks all public access and enforces bucket owner
run "en51_ac1_bucket_public_access_blocked" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.sources.block_public_acls,
      aws_s3_bucket_public_access_block.sources.block_public_policy,
      aws_s3_bucket_public_access_block.sources.ignore_public_acls,
      aws_s3_bucket_public_access_block.sources.restrict_public_buckets,
    ])
    error_message = "Block Public Access must be fully enabled on the source bucket."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.sources.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "Object ownership must be BucketOwnerEnforced."
  }

  assert {
    condition     = aws_s3_bucket.sources.bucket == "sc-dev-kb-sources-123456789012" && aws_s3_bucket.sources.force_destroy == false
    error_message = "Bucket name must be <prefix>-kb-sources-<account id> and the bucket must never be force-destroyed."
  }
}

# EN51-AC1: bucket is versioned
run "en51_ac1_bucket_versioning_enabled" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_versioning.sources.versioning_configuration).status == "Enabled"
    error_message = "Versioning must be enabled on the source bucket."
  }
}

# EN51-AC1: default encryption is SSE-KMS with the ai key and bucket key
run "en51_ac1_bucket_encrypted_with_ai_key" {
  command = plan

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.sources.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "Default encryption must be aws:kms."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.sources.rule).apply_server_side_encryption_by_default).kms_master_key_id == var.kms_key_arn
    error_message = "Default encryption must use the ai key given in kms_key_arn."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.sources.rule).bucket_key_enabled == true
    error_message = "S3 Bucket Keys must be enabled."
  }
}

# EN51-AC1: lifecycle expires noncurrent versions, delete markers and incomplete uploads
run "en51_ac1_bucket_lifecycle_rules" {
  command = plan

  variables {
    noncurrent_version_expiration_days     = 30
    abort_incomplete_multipart_upload_days = 3
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.sources.rule : r if r.id == "expire-noncurrent-versions"
    ]).noncurrent_version_expiration).noncurrent_days == 30
    error_message = "Noncurrent versions must expire after noncurrent_version_expiration_days."
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.sources.rule : r if r.id == "abort-incomplete-multipart-uploads"
    ]).abort_incomplete_multipart_upload).days_after_initiation == 3
    error_message = "Incomplete multipart uploads must be aborted after the configured days."
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.sources.rule : r if r.id == "expire-delete-markers"
    ]).expiration).expired_object_delete_marker == true
    error_message = "Expired delete markers must be removed."
  }

  assert {
    condition     = alltrue([for r in aws_s3_bucket_lifecycle_configuration.sources.rule : r.status == "Enabled"])
    error_message = "Every lifecycle rule must be enabled."
  }
}

# EN51-AC1: bucket policy is TLS-only (TLS 1.2 minimum)
run "en51_ac1_bucket_policy_tls_only" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.sources_bucket.statement :
      s.sid == "DenyInsecureTransport" && s.effect == "Deny" && anytrue([
        for c in coalesce(s.condition, []) :
        c.variable == "aws:SecureTransport" && c.test == "Bool" && contains(c.values, "false")
      ])
    ])
    error_message = "The bucket policy must deny requests without aws:SecureTransport."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.sources_bucket.statement :
      s.sid == "DenyOutdatedTls" && s.effect == "Deny" && anytrue([
        for c in coalesce(s.condition, []) :
        c.variable == "s3:TlsVersion" && c.test == "NumericLessThan" && contains(c.values, "1.2")
      ])
    ])
    error_message = "The bucket policy must deny TLS versions below 1.2."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.sources_bucket.statement :
      s.effect == "Deny" if contains(["DenyInsecureTransport", "DenyOutdatedTls"], s.sid)
    ])
    error_message = "TLS statements must be Deny statements."
  }
}

# EN51-AC1: bucket policy refuses puts that are not encrypted with the ai key
run "en51_ac1_bucket_policy_enforces_ai_key" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.sources_bucket.statement :
      s.sid == "DenyNonKmsEncryptionHeader" && s.effect == "Deny" && contains(s.actions, "s3:PutObject") && anytrue([
        for c in coalesce(s.condition, []) :
        c.variable == "s3:x-amz-server-side-encryption" && c.test == "StringNotEqualsIfExists" && contains(c.values, "aws:kms")
      ])
    ])
    error_message = "The bucket policy must deny puts that are not SSE-KMS."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.sources_bucket.statement :
      s.sid == "DenyOtherKmsKey" && s.effect == "Deny" && contains(s.actions, "s3:PutObject") && anytrue([
        for c in coalesce(s.condition, []) :
        c.variable == "s3:x-amz-server-side-encryption-aws-kms-key-id" && c.test == "StringNotEqualsIfExists" && contains(c.values, var.kms_key_arn)
      ])
    ])
    error_message = "The bucket policy must deny puts encrypted with another KMS key."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.sources_bucket.statement :
      s.sid == "DenySSEC" && s.effect == "Deny" && toset(s.actions) == toset(["s3:PutObject"]) && anytrue([
        for c in coalesce(s.condition, []) :
        c.variable == "s3:x-amz-server-side-encryption-customer-algorithm" && c.test == "Null" && toset(c.values) == toset(["false"])
      ])
    ])
    error_message = "The bucket policy must deny PutObject when an SSE-C algorithm header is present."
  }
}

# EN51-AC1: only the writer principals can write or delete documents
run "en51_ac1_bucket_policy_denies_writes_except_writers" {
  command = plan

  variables {
    writer_principal_arns = [
      "arn:aws:iam::123456789012:role/sc-dev-app-deploy",
      "arn:aws:iam::123456789012:user/sc-dev-uploader",
    ]
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.sources_bucket.statement :
      s.sid == "DenyWritesExceptWriters" && s.effect == "Deny" &&
      toset(s.resources) == toset(["arn:aws:s3:::sc-dev-kb-sources-123456789012/*"]) &&
      contains(s.actions, "s3:PutObject") && contains(s.actions, "s3:DeleteObject") && contains(s.actions, "s3:DeleteObjectVersion") &&
      anytrue([
        for c in coalesce(s.condition, []) :
        c.variable == "aws:PrincipalArn" && c.test == "ArnNotEquals" && toset(c.values) == toset(var.writer_principal_arns)
      ])
    ])
    error_message = "DenyWritesExceptWriters must deny object writes and deletes unless aws:PrincipalArn is a writer principal."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.sources_bucket.statement :
      !anytrue([for a in s.actions : startswith(a, "s3:Get") || startswith(a, "s3:List")])
    ])
    error_message = "The bucket policy must not deny reads; the knowledge base role is granted read access by IAM."
  }
}

# EN51-AC1: the bucket policy only contains Deny statements
run "en51_ac1_bucket_policy_only_deny" {
  command = plan

  assert {
    condition     = alltrue([for s in data.aws_iam_policy_document.sources_bucket.statement : s.effect == "Deny"])
    error_message = "The bucket policy must only contain Deny statements; access is granted by IAM."
  }
}

# EN51-AC2: vector bucket is encrypted with the ai key
run "en51_ac2_vector_bucket_encrypted_with_ai_key" {
  command = plan

  assert {
    condition     = aws_s3vectors_vector_bucket.this.vector_bucket_name == "sc-dev-kb-vectors"
    error_message = "The vector bucket name must be <prefix>-kb-vectors."
  }

  assert {
    condition     = one(aws_s3vectors_vector_bucket.this.encryption_configuration).sse_type == "aws:kms"
    error_message = "The vector bucket must use SSE-KMS."
  }

  assert {
    condition     = one(aws_s3vectors_vector_bucket.this.encryption_configuration).kms_key_arn == var.kms_key_arn
    error_message = "The vector bucket must be encrypted with the ai key."
  }

  assert {
    condition     = aws_s3vectors_vector_bucket.this.force_destroy == false
    error_message = "The vector bucket must never be force-destroyed."
  }
}

# EN51-AC2: index dimension and distance follow the variables, encrypted with the ai key
run "en51_ac2_vector_index_settings" {
  command = plan

  variables {
    vector_dimension = 512
    distance_metric  = "euclidean"
  }

  assert {
    condition     = aws_s3vectors_index.this.dimension == 512 && aws_s3vectors_index.this.distance_metric == "euclidean"
    error_message = "The index dimension and distance metric must follow the variables."
  }

  assert {
    condition     = aws_s3vectors_index.this.data_type == "float32"
    error_message = "The index data type must be float32."
  }

  assert {
    condition     = aws_s3vectors_index.this.vector_bucket_name == "sc-dev-kb-vectors" && aws_s3vectors_index.this.index_name == "sc-dev-kb-index"
    error_message = "The index must live in the module vector bucket and be named <prefix>-kb-index."
  }

  assert {
    condition     = one(aws_s3vectors_index.this.encryption_configuration).sse_type == "aws:kms" && one(aws_s3vectors_index.this.encryption_configuration).kms_key_arn == var.kms_key_arn
    error_message = "The index must be encrypted with the ai key."
  }

  assert {
    condition     = toset(one(aws_s3vectors_index.this.metadata_configuration).non_filterable_metadata_keys) == toset(["AMAZON_BEDROCK_TEXT", "AMAZON_BEDROCK_METADATA"])
    error_message = "The Bedrock text and metadata keys must be non-filterable."
  }
}

# EN51-AC2: cosine is the default distance metric
run "en51_ac2_default_distance_is_cosine" {
  command = plan

  assert {
    condition     = aws_s3vectors_index.this.distance_metric == "cosine"
    error_message = "The default distance metric must be cosine."
  }
}

# EN51-AC2: knowledge base is a VECTOR knowledge base stored in the S3 Vectors index
run "en51_ac2_knowledge_base_uses_s3_vectors" {
  command = plan

  assert {
    condition     = one(aws_bedrockagent_knowledge_base.this.knowledge_base_configuration).type == "VECTOR"
    error_message = "The knowledge base type must be VECTOR."
  }

  assert {
    condition     = one(aws_bedrockagent_knowledge_base.this.storage_configuration).type == "S3_VECTORS"
    error_message = "The vector store must be S3_VECTORS."
  }

  assert {
    condition     = one(one(aws_bedrockagent_knowledge_base.this.storage_configuration).s3_vectors_configuration).index_arn == "arn:aws:s3vectors:us-east-1:123456789012:bucket/sc-dev-kb-vectors/index/sc-dev-kb-index"
    error_message = "The knowledge base must store its vectors in the module index."
  }

  assert {
    condition     = aws_bedrockagent_knowledge_base.this.role_arn == "arn:aws:iam::123456789012:role/sc-dev-kb-service"
    error_message = "The knowledge base must use the module service role."
  }
}

# EN51-AC2: the embedding model is a variable, dimension and data type are passed to it
run "en51_ac2_embedding_model_is_variable" {
  command = plan

  variables {
    embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/cohere.embed-multilingual-v3"
    vector_dimension    = 1024
  }

  assert {
    condition     = one(one(aws_bedrockagent_knowledge_base.this.knowledge_base_configuration).vector_knowledge_base_configuration).embedding_model_arn == var.embedding_model_arn
    error_message = "The embedding model must follow embedding_model_arn."
  }

  assert {
    condition = one(one(one(
      one(aws_bedrockagent_knowledge_base.this.knowledge_base_configuration).vector_knowledge_base_configuration
    ).embedding_model_configuration).bedrock_embedding_model_configuration).dimensions == 1024
    error_message = "The embedding dimensions must follow vector_dimension."
  }
}

# EN51-AC2: the embedding model configuration can be turned off
run "en51_ac2_embedding_model_configuration_optional" {
  command = plan

  variables {
    enable_embedding_model_configuration = false
  }

  assert {
    condition     = length(one(one(aws_bedrockagent_knowledge_base.this.knowledge_base_configuration).vector_knowledge_base_configuration).embedding_model_configuration) == 0
    error_message = "No embedding model configuration must be set when enable_embedding_model_configuration is false."
  }
}

# EN51-AC2: a cross-region inference profile is accepted as embedding model
run "en51_ac2_eu_inference_profile_accepted" {
  command = plan

  variables {
    embedding_model_arn = "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.amazon.titan-embed-text-v2:0"
    embedding_model_additional_arns = [
      "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0",
      "arn:aws:bedrock:us-east-2::foundation-model/amazon.titan-embed-text-v2:0",
      "arn:aws:bedrock:us-west-2::foundation-model/amazon.titan-embed-text-v2:0",
    ]
  }

  assert {
    condition     = one(one(aws_bedrockagent_knowledge_base.this.knowledge_base_configuration).vector_knowledge_base_configuration).embedding_model_arn == var.embedding_model_arn
    error_message = "The inference profile must be passed to the knowledge base."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.service.statement :
      s.sid == "InvokeEmbeddingModel" && toset(s.resources) == toset([
        "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.amazon.titan-embed-text-v2:0",
        "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0",
        "arn:aws:bedrock:us-east-2::foundation-model/amazon.titan-embed-text-v2:0",
        "arn:aws:bedrock:us-west-2::foundation-model/amazon.titan-embed-text-v2:0",
      ])
    ])
    error_message = "The service role must be able to invoke the inference profile and its underlying foundation model, nothing else."
  }
}

# EN51-AC2: data source reads the bucket prefix with fixed-size chunking
run "en51_ac2_data_source_on_bucket_prefix" {
  command = plan

  variables {
    source_prefix               = "campus/"
    chunking_max_tokens         = 512
    chunking_overlap_percentage = 10
  }

  assert {
    condition     = aws_bedrockagent_data_source.sources.knowledge_base_id == "KBTEST0001"
    error_message = "The data source must belong to the module knowledge base."
  }

  assert {
    condition     = one(aws_bedrockagent_data_source.sources.data_source_configuration).type == "S3"
    error_message = "The data source type must be S3."
  }

  assert {
    condition     = one(one(aws_bedrockagent_data_source.sources.data_source_configuration).s3_configuration).bucket_arn == "arn:aws:s3:::sc-dev-kb-sources-123456789012"
    error_message = "The data source must read the source bucket."
  }

  assert {
    condition     = toset(one(one(aws_bedrockagent_data_source.sources.data_source_configuration).s3_configuration).inclusion_prefixes) == toset(["campus/"])
    error_message = "The data source must be limited to source_prefix."
  }

  assert {
    condition     = one(one(aws_bedrockagent_data_source.sources.vector_ingestion_configuration).chunking_configuration).chunking_strategy == "FIXED_SIZE"
    error_message = "The chunking strategy must be FIXED_SIZE."
  }

  assert {
    condition = one(one(one(
      aws_bedrockagent_data_source.sources.vector_ingestion_configuration
    ).chunking_configuration).fixed_size_chunking_configuration).max_tokens == 512
    error_message = "max_tokens must follow chunking_max_tokens."
  }

  assert {
    condition = one(one(one(
      aws_bedrockagent_data_source.sources.vector_ingestion_configuration
    ).chunking_configuration).fixed_size_chunking_configuration).overlap_percentage == 10
    error_message = "overlap_percentage must follow chunking_overlap_percentage."
  }

  assert {
    condition     = one(aws_bedrockagent_data_source.sources.server_side_encryption_configuration).kms_key_arn == var.kms_key_arn
    error_message = "Data transient during ingestion must be encrypted with the ai key."
  }
}

# EN51-AC3: only Bedrock can assume the role, from this account and these knowledge bases
run "en51_ac3_trust_policy_bedrock_with_source_conditions" {
  command = plan

  assert {
    condition     = length(data.aws_iam_policy_document.service_trust.statement) == 1
    error_message = "The trust policy must contain a single statement."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.service_trust.statement :
      s.effect == "Allow" && toset(s.actions) == toset(["sts:AssumeRole"]) &&
      alltrue([for p in s.principals : p.type == "Service" && p.identifiers == toset(["bedrock.amazonaws.com"])])
    ])
    error_message = "Only bedrock.amazonaws.com may assume the role."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.service_trust.statement :
      anytrue([
        for c in coalesce(s.condition, []) :
        c.variable == "aws:SourceAccount" && c.test == "StringEquals" && toset(c.values) == toset(["123456789012"])
      ])
    ])
    error_message = "The trust policy must be conditioned by aws:SourceAccount."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.service_trust.statement :
      anytrue([
        for c in coalesce(s.condition, []) :
        c.variable == "aws:SourceArn" && c.test == "ArnLike" && toset(c.values) == toset(["arn:aws:bedrock:us-east-1:123456789012:knowledge-base/*"])
      ])
    ])
    error_message = "The trust policy must be conditioned by aws:SourceArn on the knowledge bases of this account and region."
  }
}

# EN51-AC3: the role carries the permissions boundary
run "en51_ac3_role_has_permissions_boundary" {
  command = plan

  assert {
    condition     = aws_iam_role.service.permissions_boundary == "arn:aws:iam::123456789012:policy/sc-dev-boundary"
    error_message = "The service role must carry the project permissions boundary."
  }

  assert {
    condition     = aws_iam_role.service.name == "sc-dev-kb-service"
    error_message = "The role name must be <prefix>-kb-service."
  }
}

# EN51-AC3: rights are limited to the source bucket, the vector index, the embedding model and the ai key
run "en51_ac3_permissions_are_scoped" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.service.statement :
      s.sid == "ReadSourceDocuments" && s.effect == "Allow" && toset(s.actions) == toset(["s3:GetObject"]) &&
      toset(s.resources) == toset(["arn:aws:s3:::sc-dev-kb-sources-123456789012/documents/*"])
    ])
    error_message = "Object reads must be limited to the source prefix of the source bucket."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.service.statement :
      s.sid == "ListSourceBucket" && s.effect == "Allow" && toset(s.actions) == toset(["s3:ListBucket"]) &&
      toset(s.resources) == toset(["arn:aws:s3:::sc-dev-kb-sources-123456789012"])
    ])
    error_message = "Listing must be limited to the source bucket."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.service.statement :
      s.sid == "UseVectorIndex" && s.effect == "Allow" &&
      toset(s.resources) == toset(["arn:aws:s3vectors:us-east-1:123456789012:bucket/sc-dev-kb-vectors/index/sc-dev-kb-index"]) &&
      alltrue([for a in s.actions : startswith(a, "s3vectors:")])
    ])
    error_message = "s3vectors actions must be limited to the module index."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.service.statement :
      s.sid == "InvokeEmbeddingModel" && s.effect == "Allow" && toset(s.actions) == toset(["bedrock:InvokeModel"]) &&
      toset(s.resources) == toset(["arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"])
    ])
    error_message = "bedrock:InvokeModel must be limited to the embedding model."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.service.statement :
      s.sid == "UseAiKey" && s.effect == "Allow" && toset(s.resources) == toset([var.kms_key_arn]) &&
      alltrue([for a in s.actions : startswith(a, "kms:") && a != "kms:*"])
    ])
    error_message = "KMS actions must be explicit and limited to the ai key."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.service.statement :
      alltrue([for r in s.resources : r != "*"]) && alltrue([for a in s.actions : !endswith(a, "*")])
    ])
    error_message = "The service role policy must not contain a wildcard action or resource."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.service.statement : s.effect == "Allow"
    ])
    error_message = "The service role policy must only contain Allow statements."
  }
}

# EN51-AC3: listing is limited to the source prefix
run "en51_ac3_list_limited_to_source_prefix" {
  command = plan

  variables {
    source_prefix = "campus/"
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.service.statement :
      s.sid == "ListSourceBucket" && anytrue([
        for c in coalesce(s.condition, []) :
        c.variable == "s3:prefix" && c.test == "StringLike" && toset(c.values) == toset(["campus/*"])
      ])
    ])
    error_message = "ListSourceBucket must be conditioned by s3:prefix on the source prefix."
  }
}

# EN51-AC3: the ai key is only usable through S3 and Bedrock of this region and account
run "en51_ac3_kms_usage_restricted_via_service" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.service.statement :
      s.sid == "UseAiKey" && anytrue([
        for c in coalesce(s.condition, []) :
        c.variable == "kms:ViaService" && c.test == "StringEquals" &&
        toset(c.values) == toset(["s3.us-east-1.amazonaws.com", "bedrock.us-east-1.amazonaws.com"])
      ])
    ])
    error_message = "UseAiKey must be conditioned by kms:ViaService on S3 and Bedrock of the region."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.service.statement :
      s.sid == "UseAiKey" && anytrue([
        for c in coalesce(s.condition, []) :
        c.variable == "aws:ResourceAccount" && c.test == "StringEquals" && toset(c.values) == toset(["123456789012"])
      ])
    ])
    error_message = "UseAiKey must be conditioned by aws:ResourceAccount."
  }
}

# EN51-AC3: the permissions are attached to the service role
run "en51_ac3_policy_attached_to_service_role" {
  command = plan

  assert {
    condition     = aws_iam_role_policy.service.role == "sc-dev-kb-service"
    error_message = "The access policy must be attached to the service role."
  }
}

# EN51-AC1: rejects an invalid name_prefix
run "en51_ac1_rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Bad_Prefix"
  }

  expect_failures = [var.name_prefix]
}

# EN51-AC1: rejects a KMS alias instead of a key ARN
run "en51_ac1_rejects_kms_alias" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:alias/sc-dev-ai"
  }

  expect_failures = [var.kms_key_arn]
}

# EN51-AC1: rejects an empty writer list
run "en51_ac1_rejects_empty_writer_principal_arns" {
  command = plan

  variables {
    writer_principal_arns = []
  }

  expect_failures = [var.writer_principal_arns]
}

# EN51-AC1: rejects wildcards and the account root as writer principals
run "en51_ac1_rejects_wildcard_and_root_writer_principal" {
  command = plan

  variables {
    writer_principal_arns = ["arn:aws:iam::123456789012:root", "arn:aws:iam::123456789012:role/*"]
  }

  expect_failures = [var.writer_principal_arns]
}

# EN51-AC1: rejects a source prefix without trailing slash
run "en51_ac1_rejects_source_prefix_without_slash" {
  command = plan

  variables {
    source_prefix = "documents"
  }

  expect_failures = [var.source_prefix]
}

# EN51-AC1: rejects noncurrent_version_expiration_days below 1
run "en51_ac1_rejects_noncurrent_days_below_1" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 0
  }

  expect_failures = [var.noncurrent_version_expiration_days]
}

# EN51-AC1: rejects abort_incomplete_multipart_upload_days below 1
run "en51_ac1_rejects_multipart_days_below_1" {
  command = plan

  variables {
    abort_incomplete_multipart_upload_days = 0
  }

  expect_failures = [var.abort_incomplete_multipart_upload_days]
}

# EN51-AC2: rejects an embedding model that is not a Bedrock model ARN
run "en51_ac2_rejects_invalid_embedding_model_arn" {
  command = plan

  variables {
    embedding_model_arn = "amazon.titan-embed-text-v2:0"
  }

  expect_failures = [var.embedding_model_arn]
}

# EN51-AC2: rejects additional model ARNs that are not foundation models
run "en51_ac2_rejects_invalid_additional_model_arns" {
  command = plan

  variables {
    embedding_model_additional_arns = ["arn:aws:bedrock:*::foundation-model/*"]
  }

  expect_failures = [var.embedding_model_additional_arns]
}

# EN51-AC2: rejects an out-of-range vector dimension
run "en51_ac2_rejects_vector_dimension_above_4096" {
  command = plan

  variables {
    vector_dimension = 8192
  }

  expect_failures = [var.vector_dimension]
}

# EN51-AC2: rejects a vector dimension below 1
run "en51_ac2_rejects_vector_dimension_below_1" {
  command = plan

  variables {
    vector_dimension = 0
  }

  expect_failures = [var.vector_dimension]
}

# EN51-AC2: rejects an unknown distance metric
run "en51_ac2_rejects_unknown_distance_metric" {
  command = plan

  variables {
    distance_metric = "dotproduct"
  }

  expect_failures = [var.distance_metric]
}

# EN51-AC2: rejects out-of-range chunking settings
run "en51_ac2_rejects_chunking_max_tokens_below_20" {
  command = plan

  variables {
    chunking_max_tokens = 10
  }

  expect_failures = [var.chunking_max_tokens]
}

run "en51_ac2_rejects_chunking_overlap_above_99" {
  command = plan

  variables {
    chunking_overlap_percentage = 100
  }

  expect_failures = [var.chunking_overlap_percentage]
}

# EN51-AC3: rejects a permissions boundary that is not an IAM policy ARN
run "en51_ac3_rejects_invalid_permissions_boundary_arn" {
  command = plan

  variables {
    permissions_boundary_arn = "sc-dev-boundary"
  }

  expect_failures = [var.permissions_boundary_arn]
}

# EN51-AC2: rejects a wildcard region in the additional embedding model ARNs
run "en51_ac2_rejects_wildcard_region_in_additional_arns" {
  command = plan

  variables {
    embedding_model_arn             = "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.amazon.titan-embed-text-v2:0"
    embedding_model_additional_arns = ["arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0"]
  }

  expect_failures = [var.embedding_model_additional_arns]
}

# EN51-AC2: an embedding inference profile requires the underlying models of its routing regions
run "en51_ac2_rejects_embedding_profile_without_underlying_models" {
  command = plan

  variables {
    embedding_model_arn             = "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.amazon.titan-embed-text-v2:0"
    embedding_model_additional_arns = []
  }

  expect_failures = [var.embedding_model_additional_arns]
}

# EN51-AC4: object creation and deletion under the source prefix invoke kb-sync
run "en51_ac4_notification_on_create_and_delete_under_prefix" {
  command = plan

  variables {
    source_prefix = "campus/"
  }

  assert {
    condition     = length(aws_s3_bucket_notification.sources) == 1
    error_message = "A bucket notification must exist when enable_ingestion_notification is true."
  }

  assert {
    condition     = aws_s3_bucket_notification.sources[0].bucket == "sc-dev-kb-sources-123456789012"
    error_message = "The notification must be set on the source bucket."
  }

  assert {
    condition     = one(aws_s3_bucket_notification.sources[0].lambda_function).lambda_function_arn == var.ingestion_function_arn
    error_message = "The notification must target ingestion_function_arn."
  }

  assert {
    condition     = toset(one(aws_s3_bucket_notification.sources[0].lambda_function).events) == toset(["s3:ObjectCreated:*", "s3:ObjectRemoved:*"])
    error_message = "The notification must cover object creation and removal, and nothing else."
  }

  assert {
    condition     = one(aws_s3_bucket_notification.sources[0].lambda_function).filter_prefix == "campus/"
    error_message = "The notification must be limited to source_prefix."
  }
}

# EN51-AC4: only the source bucket of this account can invoke kb-sync
run "en51_ac4_lambda_permission_scoped_to_bucket_and_account" {
  command = plan

  assert {
    condition     = length(aws_lambda_permission.ingestion) == 1
    error_message = "A Lambda permission must exist when enable_ingestion_notification is true."
  }

  assert {
    condition     = aws_lambda_permission.ingestion[0].principal == "s3.amazonaws.com" && aws_lambda_permission.ingestion[0].action == "lambda:InvokeFunction"
    error_message = "Only the S3 service principal may invoke the function, with lambda:InvokeFunction."
  }

  assert {
    condition     = aws_lambda_permission.ingestion[0].function_name == var.ingestion_function_arn
    error_message = "The permission must be set on ingestion_function_arn."
  }

  assert {
    condition     = aws_lambda_permission.ingestion[0].source_arn == "arn:aws:s3:::sc-dev-kb-sources-123456789012"
    error_message = "The permission must carry aws:SourceArn set to the source bucket."
  }

  assert {
    condition     = aws_lambda_permission.ingestion[0].source_account == "123456789012"
    error_message = "The permission must carry aws:SourceAccount set to the current account."
  }
}

# EN51-AC4: the notification can be turned off
run "en51_ac4_notification_can_be_disabled" {
  command = plan

  variables {
    enable_ingestion_notification = false
    ingestion_function_arn        = null
  }

  assert {
    condition     = length(aws_s3_bucket_notification.sources) == 0 && length(aws_lambda_permission.ingestion) == 0
    error_message = "No notification and no Lambda permission must be created when enable_ingestion_notification is false."
  }
}

# EN51-AC4: rejects an enabled notification without a function
run "en51_ac4_rejects_enabled_notification_without_function" {
  command = plan

  variables {
    ingestion_function_arn = null
  }

  expect_failures = [var.ingestion_function_arn]
}

# EN51-AC4: rejects a function ARN that is not a Lambda function ARN
run "en51_ac4_rejects_invalid_function_arn" {
  command = plan

  variables {
    ingestion_function_arn = "sc-dev-kb-sync"
  }

  expect_failures = [var.ingestion_function_arn]
}

# EN51-AC5: chat can only retrieve from this knowledge base
run "en51_ac5_retrieve_policy_scoped_to_knowledge_base" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.retrieve.statement :
      s.sid == "RetrieveFromKnowledgeBase" && s.effect == "Allow" && toset(s.actions) == toset(["bedrock:Retrieve"]) &&
      toset(s.resources) == toset(["arn:aws:bedrock:us-east-1:123456789012:knowledge-base/KBTEST0001"])
    ])
    error_message = "bedrock:Retrieve must be limited to the module knowledge base."
  }
}

# EN51-AC5: chat can only invoke the configured inference profile and its underlying models
run "en51_ac5_retrieve_policy_invokes_only_configured_profile" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.retrieve.statement :
      s.sid == "InvokeInferenceProfile" && s.effect == "Allow" && toset(s.actions) == toset(["bedrock:InvokeModel"]) &&
      toset(s.resources) == toset(concat([var.inference_profile_arn], var.inference_model_arns))
    ])
    error_message = "bedrock:InvokeModel must be limited to the inference profile and its underlying foundation models."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.retrieve.statement) == 2
    error_message = "The retrieve policy must contain exactly the Retrieve and InvokeModel statements."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.retrieve.statement :
      s.effect == "Allow" &&
      alltrue([for r in s.resources : !strcontains(r, "*")]) &&
      alltrue([for a in s.actions : !strcontains(a, "*")])
    ])
    error_message = "The retrieve policy must not contain a wildcard action, resource or region."
  }
}

# EN51-AC5: kb-sync can only start and read ingestion jobs of this knowledge base
run "en51_ac5_sync_policy_scoped_to_ingestion_jobs" {
  command = plan

  assert {
    condition     = length(data.aws_iam_policy_document.sync.statement) == 1
    error_message = "The sync policy must contain a single statement."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.sync.statement :
      s.effect == "Allow" &&
      toset(s.actions) == toset(["bedrock:StartIngestionJob", "bedrock:GetIngestionJob"]) &&
      toset(s.resources) == toset(["arn:aws:bedrock:us-east-1:123456789012:knowledge-base/KBTEST0001"])
    ])
    error_message = "Ingestion job actions must be limited to the module knowledge base."
  }
}

# EN51-AC5: the policies are exposed as outputs for the platform stack
run "en51_ac5_policies_exposed_as_outputs" {
  command = plan

  # Output values and rendered JSON are unknown at plan with mocks: assert on the statement arguments that feed them.
  assert {
    condition = toset(flatten([
      for s in data.aws_iam_policy_document.retrieve.statement : s.actions
    ])) == toset(["bedrock:Retrieve", "bedrock:InvokeModel"])
    error_message = "The retrieve policy must grant only bedrock:Retrieve and bedrock:InvokeModel."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.retrieve.statement :
      length(s.resources) > 0 && alltrue([for r in s.resources : startswith(r, "arn:")])
    ])
    error_message = "Every retrieve statement must be scoped to explicit ARNs."
  }

  assert {
    condition = toset(flatten([
      for s in data.aws_iam_policy_document.sync.statement : s.actions
    ])) == toset(["bedrock:StartIngestionJob", "bedrock:GetIngestionJob"])
    error_message = "The sync policy must grant only the ingestion job actions."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.sync.statement :
      length(s.resources) > 0 && alltrue([for r in s.resources : startswith(r, "arn:")])
    ])
    error_message = "Every sync statement must be scoped to explicit ARNs."
  }
}

# EN51-AC5: rejects a wildcard region in the underlying inference models
run "en51_ac5_rejects_wildcard_region_in_inference_models" {
  command = plan

  variables {
    inference_model_arns = ["arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0"]
  }

  expect_failures = [var.inference_model_arns]
}

# EN51-AC5: rejects a wildcard model in the underlying inference models
run "en51_ac5_rejects_wildcard_model_in_inference_models" {
  command = plan

  variables {
    inference_model_arns = ["arn:aws:bedrock:us-east-1::foundation-model/*"]
  }

  expect_failures = [var.inference_model_arns]
}

# EN51-AC5: rejects an empty list of underlying inference models
run "en51_ac5_rejects_empty_inference_models" {
  command = plan

  variables {
    inference_model_arns = []
  }

  expect_failures = [var.inference_model_arns]
}

# EN51-AC5: rejects a wildcard region in the inference profile
run "en51_ac5_rejects_wildcard_region_in_inference_profile" {
  command = plan

  variables {
    inference_profile_arn = "arn:aws:bedrock:*:123456789012:inference-profile/us.anthropic.claude-sonnet-4-20250514-v1:0"
  }

  expect_failures = [var.inference_profile_arn]
}

# EN51-AC5: rejects a foundation model where an inference profile is expected
run "en51_ac5_rejects_foundation_model_as_inference_profile" {
  command = plan

  variables {
    inference_profile_arn = "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0"
  }

  expect_failures = [var.inference_profile_arn]
}

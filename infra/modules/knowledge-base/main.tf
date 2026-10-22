resource "aws_bedrockagent_knowledge_base" "this" {
  name        = local.name
  description = "Campus documents for the SmartCampus assistant (${var.name_prefix})"
  role_arn    = aws_iam_role.service.arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = var.embedding_model_arn

      dynamic "embedding_model_configuration" {
        for_each = var.enable_embedding_model_configuration ? [1] : []

        content {
          bedrock_embedding_model_configuration {
            dimensions          = var.vector_dimension
            embedding_data_type = "FLOAT32"
          }
        }
      }
    }
  }

  storage_configuration {
    type = "S3_VECTORS"

    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.this.index_arn
    }
  }

  tags = merge(var.tags, { Name = local.name })

  # The role must hold its permissions when Bedrock validates the configuration at creation.
  depends_on = [aws_iam_role_policy.service]
}

resource "aws_bedrockagent_data_source" "sources" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.this.id
  name              = "${local.name}-sources"
  description       = "Documents under ${var.source_prefix} in ${local.source_bucket_name}"

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn              = aws_s3_bucket.sources.arn
      bucket_owner_account_id = local.account_id
      inclusion_prefixes      = [var.source_prefix]
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"

      fixed_size_chunking_configuration {
        max_tokens         = var.chunking_max_tokens
        overlap_percentage = var.chunking_overlap_percentage
      }
    }
  }

  # Data kept by Bedrock while it parses and chunks the documents.
  server_side_encryption_configuration {
    kms_key_arn = var.kms_key_arn
  }
}

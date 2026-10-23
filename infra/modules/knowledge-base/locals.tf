data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  name = "${var.name_prefix}-kb"

  # S3 bucket names are global: the account ID keeps the name unique without any hardcoded value.
  # Vector bucket names are unique per account and region, so they do not need it.
  source_bucket_name = "${local.name}-sources-${local.account_id}"
  vector_bucket_name = "${local.name}-vectors"
  vector_index_name  = "${local.name}-index"
  service_role_name  = "${local.name}-service"

  # The knowledge base ID is unknown until the role exists (the knowledge base needs the role), so the trust policy
  # pins the account and the region and leaves the ID open.
  knowledge_base_arn_pattern = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:knowledge-base/*"

  # Bedrock stores the chunk text and its metadata as vector metadata. Both exceed the filterable metadata size limit
  # of S3 Vectors, so they must be declared non-filterable or ingestion fails.
  non_filterable_metadata_keys = ["AMAZON_BEDROCK_TEXT", "AMAZON_BEDROCK_METADATA"]

  embedding_model_invoke_arns = distinct(concat([var.embedding_model_arn], var.embedding_model_additional_arns))
}

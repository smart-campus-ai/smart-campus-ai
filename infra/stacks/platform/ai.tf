# Bedrock guardrail (denied topics, PII masking, prompt-attack filter, contextual grounding) and, behind
# enable_knowledge_base, the knowledge base on S3 Vectors (ADR-0007).
module "bedrock_guardrail" {
  source = "../../modules/bedrock-guardrail"

  name_prefix   = var.name_prefix
  environment   = var.env
  kms_key_arn   = local.kms_key_arns["ai"]
  denied_topics = var.guardrail_denied_topics
}

# Source documents bucket, S3 Vectors store, data source and service role. A document change invokes kb-sync (alias live).
#
# kb-sync must not depend on this module (the S3 notification needs the alias to exist, so this module depends on
# kb-sync): kb-sync reads the knowledge base identifiers from SSM at runtime, and its ingestion policy is attached in
# iam.tf once both exist.
module "knowledge_base" {
  count = var.enable_knowledge_base ? 1 : 0

  source = "../../modules/knowledge-base"

  name_prefix                   = var.name_prefix
  kms_key_arn                   = local.kms_key_arns["ai"]
  permissions_boundary_arn      = local.permissions_boundary_arn
  writer_principal_arns         = var.knowledge_base_writer_principal_arns
  embedding_model_arn           = "arn:${local.partition}:bedrock:${local.region}::foundation-model/${var.embedding_model_id}"
  vector_dimension              = var.embedding_dimension
  inference_profile_arn         = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:inference-profile/${var.chat_inference_profile_id}"
  inference_model_arns          = [for region in var.chat_inference_regions : "arn:${local.partition}:bedrock:${region}::foundation-model/${var.chat_foundation_model_id}"]
  ingestion_function_arn        = module.kb_sync.alias_arn
  enable_ingestion_notification = true
}

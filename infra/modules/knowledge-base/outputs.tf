output "source_bucket_name" {
  description = "Name of the source documents bucket (target of the S3 event notification to kb-sync)."
  value       = aws_s3_bucket.sources.id
}

output "source_bucket_arn" {
  description = "ARN of the source documents bucket, scoped in the writer and kb-sync policies."
  value       = aws_s3_bucket.sources.arn
}

output "source_prefix" {
  description = "Key prefix of the source documents (filter of the S3 event notification)."
  value       = var.source_prefix
}

output "vector_bucket_name" {
  description = "Name of the S3 Vectors vector bucket."
  value       = aws_s3vectors_vector_bucket.this.vector_bucket_name
}

output "vector_bucket_arn" {
  description = "ARN of the S3 Vectors vector bucket."
  value       = aws_s3vectors_vector_bucket.this.vector_bucket_arn
}

output "vector_index_name" {
  description = "Name of the S3 Vectors index."
  value       = aws_s3vectors_index.this.index_name
}

output "vector_index_arn" {
  description = "ARN of the S3 Vectors index."
  value       = aws_s3vectors_index.this.index_arn
}

output "knowledge_base_id" {
  description = "ID of the knowledge base (Retrieve calls and ingestion jobs)."
  value       = aws_bedrockagent_knowledge_base.this.id
}

output "knowledge_base_arn" {
  description = "ARN of the knowledge base, scoped in the chat and kb-sync policies (EN-51 AC5)."
  value       = aws_bedrockagent_knowledge_base.this.arn
}

output "data_source_id" {
  description = "ID of the data source on the source bucket (StartIngestionJob)."
  value       = aws_bedrockagent_data_source.sources.data_source_id
}

output "policy_json_retrieve" {
  description = "IAM policy document for the chat function: bedrock:Retrieve on the knowledge base and bedrock:InvokeModel on the inference profile and its underlying models (EN-51 AC5)."
  value       = data.aws_iam_policy_document.retrieve.json
}

output "policy_json_sync" {
  description = "IAM policy document for the kb-sync function: StartIngestionJob and GetIngestionJob on the knowledge base (EN-51 AC5)."
  value       = data.aws_iam_policy_document.sync.json
}

output "service_role_arn" {
  description = "ARN of the knowledge base service role."
  value       = aws_iam_role.service.arn
}

output "service_role_name" {
  description = "Name of the knowledge base service role."
  value       = aws_iam_role.service.name
}

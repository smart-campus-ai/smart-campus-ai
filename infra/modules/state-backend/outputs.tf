output "bucket_name" {
  description = "Name of the state bucket (backend.hcl \"bucket\")."
  value       = aws_s3_bucket.state.id
}

output "bucket_arn" {
  description = "ARN of the state bucket, scoped in the EN-13 CI role policies."
  value       = aws_s3_bucket.state.arn
}

output "kms_key_arn" {
  description = "ARN of the state KMS key (backend.hcl \"kms_key_id\" and the encryption block key provider)."
  value       = aws_kms_key.this.arn
}

output "kms_key_id" {
  description = "ID of the state KMS key."
  value       = aws_kms_key.this.key_id
}

output "kms_alias_name" {
  description = "Alias of the state KMS key."
  value       = aws_kms_alias.this.name
}

output "kms_alias_arn" {
  description = "ARN of the alias of the state KMS key."
  value       = aws_kms_alias.this.arn
}

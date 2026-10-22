output "state_bucket_name" {
  description = "State bucket name: value of \"bucket\" in infra/envs/<env>/backend.hcl."
  value       = module.state_backend.bucket_name
}

output "state_bucket_arn" {
  description = "State bucket ARN: input of the EN-13 CI role policies."
  value       = module.state_backend.bucket_arn
}

output "state_kms_key_arn" {
  description = "State KMS key ARN: \"kms_key_id\" in backend.hcl, TF_VAR_state_kms_key_arn for the stacks, and input of the EN-13 CI role policies."
  value       = module.state_backend.kms_key_arn
}

output "state_kms_alias_name" {
  description = "State KMS key alias (informational; the backend and the encryption block need the key ARN)."
  value       = module.state_backend.kms_alias_name
}

output "aws_region" {
  description = "Region of the state backend: value of \"region\" in backend.hcl."
  value       = var.aws_region
}

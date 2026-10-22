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

output "github_plan_role_arn" {
  description = "Plan role ARN. Store it as the repository-level GitHub variable AWS_PLAN_ROLE_ARN (pull_request jobs run outside any environment). A variable, not a secret."
  value       = module.github_oidc.plan_role_arn
}

output "github_apply_role_arns" {
  description = "Apply role ARNs keyed by environment. Store each one as the AWS_APPLY_ROLE_ARN variable of the GitHub environment of the same name (dev, prod). Variables, not secrets."
  value       = module.github_oidc.apply_role_arns
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider used by the CI roles."
  value       = module.github_oidc.oidc_provider_arn
}

output "ci_boundary_arn" {
  description = "Permissions boundary of the CI roles."
  value       = module.github_oidc.ci_boundary_arn
}

output "workload_boundary_arns" {
  description = "Permissions boundaries keyed by environment (dev, prod). Every role created by the apply role of an environment must carry the boundary of that environment: pass it as permissions_boundary on every aws_iam_role of the stacks (TF_VAR_workload_boundary_arn)."
  value       = module.github_oidc.workload_boundary_arns
}

output "aws_region" {
  description = "Region of the state backend: value of \"region\" in backend.hcl."
  value       = var.aws_region
}

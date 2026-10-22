output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider used by the trust policies (created here or passed in)."
  value       = local.oidc_provider_arn
}

output "plan_role_arn" {
  description = "ARN of the read-only plan role. Store it as the repository-level GitHub variable AWS_PLAN_ROLE_ARN: pull_request jobs run outside any environment."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arns" {
  description = "ARNs of the apply roles, keyed by environment (dev, prod). Store each one as the AWS_APPLY_ROLE_ARN variable of the matching GitHub environment."
  value       = { for e, role in aws_iam_role.apply : e => role.arn }
}

output "ci_boundary_arn" {
  description = "ARN of the permissions boundary attached to the CI roles."
  value       = aws_iam_policy.ci_boundary.arn
}

output "workload_boundary_arns" {
  description = "ARNs of the permissions boundaries that every role created by an apply role must carry, keyed by environment (dev, prod). A stack sets the boundary of its own environment as permissions_boundary on every aws_iam_role."
  value       = { for e, policy in aws_iam_policy.workload_boundary : e => policy.arn }
}

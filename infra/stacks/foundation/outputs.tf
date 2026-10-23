output "name_prefix" {
  description = "Resource name prefix of this environment (sc-<env>)."
  value       = var.name_prefix
}

output "kms_key_arns" {
  description = "ARN of each domain key (data, logs, ai). Published to SSM at /smartcampus/<env>/foundation/kms/<domain>/arn."
  value       = module.kms_keys.key_arns
}

output "alerts_topic_arn" {
  description = "ARN of the ops alerts SNS topic. Published to SSM at /smartcampus/<env>/foundation/alerts/topic-arn."
  value       = aws_sns_topic.alerts.arn
}

output "budget_arn" {
  description = "ARN of the monthly budget, null when enable_budget is false. Published to SSM at /smartcampus/<env>/foundation/budget_arn when enabled."
  value       = one(module.budget[*].budget_arn)
}

output "ssm_parameter_names" {
  description = "Names of the SSM parameters published for the platform stack."
  value = concat(
    [for p in aws_ssm_parameter.kms_key_arn : p.name],
    [aws_ssm_parameter.alerts_topic_arn.name],
    aws_ssm_parameter.budget_arn[*].name,
  )
}

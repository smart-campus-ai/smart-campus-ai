output "key_arns" {
  description = "ARN of each key, by domain. Published to SSM by the foundation stack (EN-14 AC4)."
  value       = { for domain, key in aws_kms_key.this : domain => key.arn }
}

output "key_ids" {
  description = "ID of each key, by domain."
  value       = { for domain, key in aws_kms_key.this : domain => key.key_id }
}

output "alias_names" {
  description = "Alias of each key, by domain (alias/<name_prefix>-<domain>)."
  value       = { for domain, alias in aws_kms_alias.this : domain => alias.name }
}

output "alias_arns" {
  description = "ARN of the alias of each key, by domain."
  value       = { for domain, alias in aws_kms_alias.this : domain => alias.arn }
}

output "deletion_alert_rule_arn" {
  description = "ARN of the key deletion alert EventBridge rule, or null when alerts are disabled. Use it as aws:SourceArn in the alert topic policy."
  value       = one(aws_cloudwatch_event_rule.key_protection[*].arn)
}

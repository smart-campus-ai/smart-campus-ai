output "admins_topic_arn" {
  description = "ARN of the admins SNS topic (security tickets, SLA escalation). The tickets and escalation roles get sns:Publish on this ARN only."
  value       = aws_sns_topic.this["admins"].arn
}

output "ops_topic_arn" {
  description = "ARN of the ops SNS topic (CloudWatch alarms, budgets, SES delivery events)."
  value       = aws_sns_topic.this["ops"].arn
}

output "ses_identity_arn" {
  description = "ARN of the SES sender e-mail identity, or null when only sender_domain is set. Sensitive: the ARN contains the sender e-mail address."
  value       = one(aws_sesv2_email_identity.sender[*].arn)
  sensitive   = true
}

output "ses_domain_identity_arn" {
  description = "ARN of the SES sender domain identity, or null when sender_domain is not set."
  value       = one(aws_sesv2_email_identity.sender_domain[*].arn)
}

output "ses_domain_dkim_tokens" {
  description = "DKIM tokens of the sender domain: publish <token>._domainkey.<domain> CNAME records pointing to <token>.dkim.amazonses.com to verify the domain. Empty when sender_domain is not set."
  value       = try(aws_sesv2_email_identity.sender_domain[0].dkim_signing_attributes[0].tokens, [])
}

output "configuration_set_arn" {
  description = "ARN of the SES configuration set, or null when enable_configuration_set is false."
  value       = one(aws_sesv2_configuration_set.this[*].arn)
}

output "send_email_policy_json" {
  description = "IAM policy document (JSON) granting ses:SendEmail on the sender identity ARN(s) with the ses:FromAddress condition, to attach to the notifier role. Sensitive: it contains the sender e-mail address."
  value       = data.aws_iam_policy_document.send_email.json
  sensitive   = true
}

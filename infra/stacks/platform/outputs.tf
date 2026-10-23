output "name_prefix" {
  description = "Resource name prefix of this environment (sc-<env>)."
  value       = var.name_prefix
}

output "site_url" {
  description = "HTTPS URL of the application on the CloudFront domain (no custom domain, ADR-0003)."
  value       = module.static_site.site_url
}

output "site_bucket_name" {
  description = "Name of the private SPA bucket, target of the front deployment."
  value       = module.static_site.bucket_name
}

output "site_distribution_id" {
  description = "ID of the CloudFront distribution (cache invalidation after a front deployment)."
  value       = module.static_site.distribution_id
}

output "site_distribution_arn" {
  description = "ARN of the CloudFront distribution, for the aws:SourceArn condition of the data key policy (OAC reads of the SPA bucket)."
  value       = module.static_site.distribution_arn
}

output "api_invoke_url" {
  description = "Invoke URL of the REST API stage (the application reaches it through /api/* on the CloudFront domain)."
  value       = module.rest_api.invoke_url
}

output "user_pool_id" {
  description = "ID of the Cognito user pool."
  value       = module.identity.user_pool_id
}

output "client_id" {
  description = "ID of the public SPA app client of the user pool."
  value       = module.identity.client_id
}

output "hosted_ui_base_url" {
  description = "Base URL of the Cognito hosted domain (/oauth2/authorize, /oauth2/token, /logout)."
  value       = module.identity.hosted_ui_base_url
}

output "lambda_function_names" {
  description = "Deployed names of the eight Lambda functions by short name; the application pipeline deploys the code and moves the live alias."
  value       = local.lambda_function_names
}

output "tickets_table_name" {
  description = "Name of the tickets DynamoDB table."
  value       = module.tickets_store.table_name
}

output "chat_sessions_table_name" {
  description = "Name of the chat sessions DynamoDB table."
  value       = module.chat_sessions.table_name
}

output "attachments_bucket_name" {
  description = "Name of the attachments bucket."
  value       = module.attachments_bucket.bucket_name
}

output "admins_topic_arn" {
  description = "ARN of the admins SNS topic."
  value       = module.notifications.admins_topic_arn
}

output "ops_topic_arn" {
  description = "ARN of the ops SNS topic, to be used by the alarms and budgets of the observability modules."
  value       = module.notifications.ops_topic_arn
}

output "ses_domain_dkim_tokens" {
  description = "DKIM tokens of the SES sender domain, to publish as CNAME records in the DNS of the domain owner. Empty when sender_domain is not set."
  value       = module.notifications.ses_domain_dkim_tokens
}

output "guardrail_id" {
  description = "ID of the Bedrock guardrail."
  value       = module.bedrock_guardrail.guardrail_id
}

output "knowledge_base_id" {
  description = "ID of the Bedrock knowledge base, or null when enable_knowledge_base is false."
  value       = one(module.knowledge_base[*].knowledge_base_id)
}

output "ssm_parameter_names" {
  description = "Names of the SSM parameters published for the application pipeline under /smartcampus/<env>/platform/."
  value       = sort([for parameter in aws_ssm_parameter.published : parameter.name])
}

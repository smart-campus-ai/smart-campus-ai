output "user_pool_id" {
  description = "ID of the Cognito user pool."
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "ARN of the Cognito user pool (API Gateway Cognito authorizer, pre-token trigger permission)."
  value       = aws_cognito_user_pool.this.arn
}

output "client_id" {
  description = "ID of the SPA app client (public, no secret)."
  value       = aws_cognito_user_pool_client.spa.id
}

output "issuer_url" {
  description = "Token issuer (iss claim) and OIDC discovery base URL of the user pool."
  value       = "https://${aws_cognito_user_pool.this.endpoint}"
}

output "hosted_ui_base_url" {
  description = "Base URL of the Cognito hosted domain (/oauth2/authorize, /oauth2/token, /logout)."
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.region}.amazoncognito.com"
}

output "group_names" {
  description = "Names of the user pool groups, as they appear in the cognito:groups claim."
  value       = [for group in aws_cognito_user_group.this : group.name]
}

output "test_user_password_parameter_names" {
  description = "SSM parameter names (not the values) holding the test user temporary passwords, by test user key. Empty unless enable_test_users is true."
  value       = { for key, parameter in aws_ssm_parameter.test_user_password : key => parameter.name }
}

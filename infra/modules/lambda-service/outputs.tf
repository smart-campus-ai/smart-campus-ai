output "function_name" {
  description = "Name of the function."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the function (unqualified). Integrations must use alias_arn."
  value       = aws_lambda_function.this.arn
}

output "alias_name" {
  description = "Name of the live alias."
  value       = aws_lambda_alias.live.name
}

output "alias_arn" {
  description = "ARN of the live alias, to use for every integration (API Gateway, event source mapping, Scheduler target, permissions)."
  value       = aws_lambda_alias.live.arn
}

output "alias_invoke_arn" {
  description = "Invoke ARN of the live alias (API Gateway integration URI)."
  value       = aws_lambda_alias.live.invoke_arn
}

output "role_name" {
  description = "Name of the execution role."
  value       = aws_iam_role.this.name
}

output "role_arn" {
  description = "ARN of the execution role."
  value       = aws_iam_role.this.arn
}

output "log_group_name" {
  description = "Name of the function log group."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the function log group."
  value       = aws_cloudwatch_log_group.this.arn
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue, or null when enable_dlq is false (alarm on its depth)."
  value       = one(aws_sqs_queue.dlq[*].arn)
}

output "dlq_name" {
  description = "Name of the dead-letter queue, or null when enable_dlq is false (CloudWatch metric dimension)."
  value       = one(aws_sqs_queue.dlq[*].name)
}

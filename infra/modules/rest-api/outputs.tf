output "rest_api_id" {
  description = "ID of the REST API."
  value       = aws_api_gateway_rest_api.this.id
}

output "rest_api_arn" {
  description = "ARN of the REST API."
  value       = aws_api_gateway_rest_api.this.arn
}

output "execution_arn" {
  description = "Execution ARN of the REST API (prefix of the aws:SourceArn values of the invoke permissions)."
  value       = aws_api_gateway_rest_api.this.execution_arn
}

output "stage_name" {
  description = "Name of the stage."
  value       = aws_api_gateway_stage.this.stage_name
}

output "stage_arn" {
  description = "ARN of the stage (resource of the WAF association)."
  value       = aws_api_gateway_stage.this.arn
}

output "invoke_url" {
  description = "Invoke URL of the stage (https://<id>.execute-api.<region>.amazonaws.com/<stage>)."
  value       = aws_api_gateway_stage.this.invoke_url
}

output "origin_domain_name" {
  description = "Domain name of the API, used as the domain_name of the CloudFront /api/* origin (EN-21)."
  value       = "${aws_api_gateway_rest_api.this.id}.execute-api.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}"
}

output "origin_path" {
  description = "Path prefix of the stage, used as the origin_path of the CloudFront /api/* origin (EN-21)."
  value       = "/${aws_api_gateway_stage.this.stage_name}"
}

output "access_log_group_name" {
  description = "Name of the access log group."
  value       = aws_cloudwatch_log_group.access.name
}

output "access_log_group_arn" {
  description = "ARN of the access log group."
  value       = aws_cloudwatch_log_group.access.arn
}

output "execution_log_group_name" {
  description = "Name of the execution log group."
  value       = aws_cloudwatch_log_group.execution.name
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard."
  value       = aws_cloudwatch_dashboard.this.dashboard_name
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard."
  value       = aws_cloudwatch_dashboard.this.dashboard_arn
}

output "alarm_arns" {
  description = "ARNs of every alarm created by the module, keyed by alarm name."
  value = merge(
    { for a in aws_cloudwatch_metric_alarm.api_5xx_rate : a.alarm_name => a.arn },
    { for a in aws_cloudwatch_metric_alarm.api_latency_p95 : a.alarm_name => a.arn },
    { for a in aws_cloudwatch_metric_alarm.lambda_errors : a.alarm_name => a.arn },
    { for a in aws_cloudwatch_metric_alarm.lambda_throttles : a.alarm_name => a.arn },
    { for a in aws_cloudwatch_metric_alarm.dlq_depth : a.alarm_name => a.arn },
    { for a in aws_cloudwatch_metric_alarm.waf_blocked_requests : a.alarm_name => a.arn },
    { for a in aws_cloudwatch_metric_alarm.cloudfront_waf_blocked_requests : a.alarm_name => a.arn },
    { for a in aws_cloudwatch_metric_alarm.log_metric_filter : a.alarm_name => a.arn },
  )
}

output "metric_namespace" {
  description = "CloudWatch namespace of the custom metrics produced by the log metric filters."
  value       = local.metric_namespace
}

output "metric_filter_names" {
  description = "Names of the log metric filters, keyed by filter key (auth-failures for the authentication failure filter)."
  value       = { for k, f in aws_cloudwatch_log_metric_filter.this : k => f.name }
}

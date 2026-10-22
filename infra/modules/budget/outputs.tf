output "budget_name" {
  description = "Name of the monthly cost budget."
  value       = aws_budgets_budget.monthly.name
}

output "budget_arn" {
  description = "ARN of the monthly cost budget."
  value       = aws_budgets_budget.monthly.arn
}

output "anomaly_monitor_arn" {
  description = "ARN of the Cost Anomaly Detection monitor, null when enable_anomaly_detection is false."
  value       = one(aws_ce_anomaly_monitor.this[*].arn)
}

output "anomaly_subscription_arn" {
  description = "ARN of the Cost Anomaly Detection subscription, null when enable_anomaly_detection is false."
  value       = one(aws_ce_anomaly_subscription.this[*].arn)
}

output "topic_policy_statement_json" {
  description = "IAM policy document (JSON) with the statement allowing budgets.amazonaws.com and costalerts.amazonaws.com to publish to sns_topic_arn (conditioned on aws:SourceAccount). To be merged into the topic policy by the notifications module. Null when sns_topic_arn is null."
  value       = one(data.aws_iam_policy_document.topic_publish[*].json)
}

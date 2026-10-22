output "table_name" {
  description = "Name of the kpi table (KPI_TABLE environment variable of kpi and kpi-aggregator)."
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "ARN of the kpi table, for the IAM policy of the kpi (read) function."
  value       = aws_dynamodb_table.this.arn
}

output "aggregator_policy_arn" {
  description = "ARN of the IAM policy to attach to the kpi-aggregator role: stream read, kpi write, failure destination, KMS use. No access to the tickets table."
  value       = aws_iam_policy.aggregator.arn
}

output "dlq_arn" {
  description = "ARN of the SQS queue receiving the batches the stream mapping could not process (for the DLQ depth alarm)."
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  description = "Name of the failure queue (CloudWatch dimension QueueName for the DLQ depth alarm)."
  value       = aws_sqs_queue.dlq.name
}

output "event_source_mapping_uuid" {
  description = "UUID of the tickets stream -> kpi-aggregator event source mapping."
  value       = aws_lambda_event_source_mapping.this.uuid
}

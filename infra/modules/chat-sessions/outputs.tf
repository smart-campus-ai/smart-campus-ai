output "table_name" {
  description = "Name of the chat-sessions table (environment variable of the chat function)."
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "ARN of the chat-sessions table."
  value       = aws_dynamodb_table.this.arn
}

output "index_arns" {
  description = "ARNs of the global secondary indexes (empty when enable_owner_index is false), for IAM policies written outside this module."
  value       = local.index_arns
}

output "owner_index_name" {
  description = "Name of the index that lists the sessions of an owner, or null when enable_owner_index is false."
  value       = var.enable_owner_index ? "by-owner" : null
}

output "hash_key" {
  description = "Name of the partition key attribute."
  value       = var.hash_key
}

output "range_key" {
  description = "Name of the sort key attribute, or null when the table has no sort key."
  value       = var.range_key
}

output "ttl_attribute_name" {
  description = "Name of the TTL attribute; the chat function writes the expiry (epoch seconds) in it."
  value       = var.ttl_attribute_name
}

output "retention_days" {
  description = "Configured retention of a chat session, in days; the chat function uses it to compute the TTL attribute."
  value       = var.retention_days
}

output "stream_arn" {
  description = "ARN of the table stream, or null when enable_stream is false."
  value       = var.enable_stream ? aws_dynamodb_table.this.stream_arn : null
}

output "access_policy_json" {
  description = "IAM policy document (JSON) granting item access (Get, BatchGet, Put, Update, Delete, Query; no Scan) on the table and its indexes, to attach to the role of the chat function."
  value       = data.aws_iam_policy_document.access.json
}

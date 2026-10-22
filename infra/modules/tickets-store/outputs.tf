output "table_name" {
  description = "Name of the tickets table (TICKETS_TABLE environment variable of the functions)."
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "ARN of the tickets table, for the IAM policies of the functions (table-level actions)."
  value       = aws_dynamodb_table.this.arn
}

output "index_arns" {
  description = "ARNs of the global secondary indexes keyed by index name (by-owner, by-status), for the Query permission of the functions."
  value = {
    (local.owner_index_name)  = "${aws_dynamodb_table.this.arn}/index/${local.owner_index_name}"
    (local.status_index_name) = "${aws_dynamodb_table.this.arn}/index/${local.status_index_name}"
  }
}

output "stream_arn" {
  description = "ARN of the table stream (NEW_AND_OLD_IMAGES), consumed by notifier and kpi-aggregator."
  value       = aws_dynamodb_table.this.stream_arn
}

output "owner_index_name" {
  description = "Name of the owner GSI (owner sub + creation date)."
  value       = local.owner_index_name
}

output "status_index_name" {
  description = "Name of the status GSI (status + creation date)."
  value       = local.status_index_name
}

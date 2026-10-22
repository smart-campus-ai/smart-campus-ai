output "schedule_group_name" {
  description = "Name of the SLA schedule group (<name_prefix>-sla), passed as GroupName when tickets creates a schedule."
  value       = aws_scheduler_schedule_group.sla.name
}

output "schedule_group_arn" {
  description = "ARN of the SLA schedule group."
  value       = aws_scheduler_schedule_group.sla.arn
}

output "scheduler_role_arn" {
  description = "ARN of the scheduler execution role, passed as the target RoleArn of each schedule. tickets may pass this role and no other (iam:PassRole)."
  value       = aws_iam_role.scheduler.arn
}

output "scheduler_role_name" {
  description = "Name of the scheduler execution role."
  value       = aws_iam_role.scheduler.name
}

output "tickets_schedules_policy_json" {
  description = "IAM policy document (JSON) for the tickets function role: scheduler:CreateSchedule and scheduler:DeleteSchedule on the SLA group schedules only, and iam:PassRole on the scheduler execution role only, to the scheduler service. Attach it to the tickets role as an extra policy."
  value       = data.aws_iam_policy_document.tickets_schedules.json
}

output "dlq_arn" {
  description = "ARN of the encrypted dead-letter queue, to set as the dead_letter_config of each schedule target. Null when enable_dlq is false."
  value       = one(aws_sqs_queue.dlq[*].arn)
}

output "dlq_name" {
  description = "Name of the dead-letter queue, for alarms on its depth. Null when enable_dlq is false."
  value       = one(aws_sqs_queue.dlq[*].name)
}

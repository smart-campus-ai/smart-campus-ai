output "log_bucket_name" {
  description = "Name of the security log bucket. Null when neither CloudTrail nor Config is enabled."
  value       = one(aws_s3_bucket.logs[*].id)
}

output "log_bucket_arn" {
  description = "ARN of the security log bucket. Null when neither CloudTrail nor Config is enabled."
  value       = one(aws_s3_bucket.logs[*].arn)
}

output "cloudtrail_arn" {
  description = "ARN of the multi-region trail. Null when enable_cloudtrail is false."
  value       = one(aws_cloudtrail.this[*].arn)
}

output "cloudtrail_log_group_name" {
  description = "Name of the CloudWatch log group that receives the trail events (input of metric filters and alarms). Null when enable_cloudtrail is false."
  value       = one(aws_cloudwatch_log_group.trail[*].name)
}

output "cloudtrail_log_group_arn" {
  description = "ARN of the CloudWatch log group that receives the trail events. Null when enable_cloudtrail is false."
  value       = one(aws_cloudwatch_log_group.trail[*].arn)
}

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector. Null when enable_guardduty is false."
  value       = one(aws_guardduty_detector.this[*].id)
}

output "securityhub_fsbp_standards_arn" {
  description = "ARN of the AWS Foundational Security Best Practices standard subscribed in Security Hub. Null when enable_securityhub is false."
  value       = one(aws_securityhub_standards_subscription.fsbp[*].standards_arn)
}

output "config_recorder_name" {
  description = "Name of the AWS Config recorder. Null when enable_config is false."
  value       = one(aws_config_configuration_recorder.this[*].name)
}

output "access_analyzer_arn" {
  description = "ARN of the account-level IAM Access Analyzer. Null when enable_access_analyzer is false."
  value       = one(aws_accessanalyzer_analyzer.this[*].arn)
}

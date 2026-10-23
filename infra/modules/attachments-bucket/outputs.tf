output "bucket_name" {
  description = "Name of the attachments bucket (BUCKET env var of \"tickets\")."
  value       = aws_s3_bucket.attachments.id
}

output "bucket_arn" {
  description = "ARN of the attachments bucket, scoped in the IAM policies of the roles that use it."
  value       = aws_s3_bucket.attachments.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the attachments bucket (target of the presigned POST)."
  value       = aws_s3_bucket.attachments.bucket_regional_domain_name
}

output "malware_protection_plan_arn" {
  description = "ARN of the GuardDuty Malware Protection plan, null when enable_malware_protection is false."
  value       = one(aws_guardduty_malware_protection_plan.attachments[*].arn)
}

output "malware_protection_role_arn" {
  description = "ARN of the malware protection service role, null when enable_malware_protection is false."
  value       = one(aws_iam_role.malware[*].arn)
}

output "scan_status_tag_key" {
  description = "Key of the object tag written by GuardDuty with the scan result."
  value       = local.scan_status_tag_key
}

output "scan_status_clean_tag_value" {
  description = "Value of the scan tag on an object with no threat found; the only objects that can be read when malware protection is enabled."
  value       = local.scan_status_clean_tag
}

output "attachments_prefix" {
  description = "Key prefix of the attachments; the key of the presigned POST must start with it."
  value       = var.attachments_prefix
}

output "max_upload_bytes" {
  description = "Maximum size of an attachment in bytes (10485760 = 10 MiB): upper bound of the content-length-range condition of the presigned POST policy."
  value       = var.max_upload_bytes
}

output "allowed_content_types" {
  description = "Content types accepted for an attachment: values of the Content-Type condition of the presigned POST policy."
  value       = var.allowed_content_types
}

output "policy_json_tickets_rw" {
  description = "IAM policy document (JSON) for the \"tickets\" role: PutObject and GetObject limited to the attachments prefix of the bucket. Attach it to the role in the module that owns the role."
  value       = data.aws_iam_policy_document.tickets_rw.json
}

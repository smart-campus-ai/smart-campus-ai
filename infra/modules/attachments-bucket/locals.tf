data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  # S3 bucket names are global: the account ID keeps the name unique without any hardcoded value.
  bucket_name = "${var.name_prefix}-attachments-${local.account_id}"

  # ARNs are built from names so the bucket policy, the role policy and the trust policy do not depend on each
  # other through computed attributes.
  bucket_arn         = "arn:${local.partition}:s3:::${local.bucket_name}"
  bucket_objects_arn = "${local.bucket_arn}/*"

  malware_role_name = "${var.name_prefix}-attachments-malware-scan"
  malware_role_arn  = "arn:${local.partition}:iam::${local.account_id}:role/${local.malware_role_name}"

  # The plan ID only exists after creation: the trust policy is scoped to the plans of this account and region.
  malware_plan_arn_pattern = "arn:${local.partition}:guardduty:${local.region}:${local.account_id}:malware-protection-plan/*"

  # Rules created and owned by GuardDuty in the account to receive the S3 object events.
  malware_event_rule_arn = "arn:${local.partition}:events:${local.region}:${local.account_id}:rule/DO-NOT-DELETE-AmazonGuardDutyMalwareProtectionS3*"

  # Tag written by GuardDuty on every scanned object; the value of a clean object.
  scan_status_tag_key   = "GuardDutyMalwareScanStatus"
  scan_status_clean_tag = "NO_THREATS_FOUND"
}

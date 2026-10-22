resource "aws_guardduty_detector" "this" {
  count = var.enable_guardduty ? 1 : 0

  # checkov:skip=CKV2_AWS_3: The workshop account already has a GuardDuty detector; this module only creates one when explicitly enabled.
  enable = true

  # Findings reach EventBridge within 15 minutes instead of the 6-hour default, which the EN-16 alarms rely on.
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = merge(var.tags, { Name = "${var.name_prefix}-guardduty" })
}

resource "aws_guardduty_detector_feature" "s3_data_events" {
  count = var.enable_guardduty && var.enable_guardduty_s3_protection ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "ebs_malware_protection" {
  count = var.enable_guardduty && var.enable_guardduty_malware_protection ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "EBS_MALWARE_PROTECTION"
  status      = "ENABLED"
}

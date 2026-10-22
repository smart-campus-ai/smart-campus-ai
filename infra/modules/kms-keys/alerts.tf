# Alert when one of these keys is disabled or scheduled for deletion (follow-up of EN-12). EventBridge receives the
# CloudTrail management events of the region on the default bus, so a trail is only needed for the events to exist.
resource "aws_cloudwatch_event_rule" "key_protection" {
  count = var.enable_deletion_alerts ? 1 : 0

  name        = "${var.name_prefix}-kms-key-protection"
  description = "ScheduleKeyDeletion or DisableKey called on a ${var.name_prefix} domain key"

  event_pattern = jsonencode({
    source      = ["aws.kms"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["kms.amazonaws.com"]
      eventName   = ["DisableKey", "ScheduleKeyDeletion"]
      requestParameters = {
        keyId = local.protected_key_identifiers
      }
    }
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-kms-key-protection", Environment = var.environment })
}

resource "aws_cloudwatch_event_target" "key_protection" {
  count = var.enable_deletion_alerts ? 1 : 0

  rule      = aws_cloudwatch_event_rule.key_protection[0].name
  target_id = "sns-alerts"
  arn       = var.alert_topic_arn
}

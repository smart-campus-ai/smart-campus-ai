# Alert when one of these keys is disabled, scheduled for deletion, loses its rotation or its alias, or has its policy
# rewritten (follow-up of EN-12). PutKeyPolicy matters because the account root keeps it for lockout recovery: it is the
# one event that reveals a policy bypass. EventBridge receives the CloudTrail management events of the region on the
# default bus, so a trail is only needed for the events to exist.
# DeleteAlias identifies the alias, not the key, hence the second branch of the pattern.
resource "aws_cloudwatch_event_rule" "key_protection" {
  count = var.enable_deletion_alerts ? 1 : 0

  name        = "${var.name_prefix}-kms-key-protection"
  description = "Key deletion, disabling, rotation, policy or alias change on a ${var.name_prefix} domain key"

  event_pattern = jsonencode({
    source      = ["aws.kms"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["kms.amazonaws.com"]
      "$or" = [
        {
          eventName = ["DisableKey", "DisableKeyRotation", "PutKeyPolicy", "ScheduleKeyDeletion"]
          requestParameters = {
            keyId = local.protected_key_identifiers
          }
        },
        {
          eventName = ["DeleteAlias"]
          requestParameters = {
            aliasName = local.protected_alias_names
          }
        },
      ]
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

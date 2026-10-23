resource "aws_sns_topic" "this" {
  for_each = local.topics

  name              = each.value.name
  display_name      = each.value.name
  kms_master_key_id = var.kms_key_arn
  signature_version = 2

  tags = merge(var.tags, { Name = each.value.name })
}

# Topic policy:
# - DenyInsecureTransport: sns:Publish on the topic is refused over plain HTTP.
# - AllowPublishPrincipals: only the listed IAM roles of this account may publish (aws:PrincipalAccount; IAM must allow them as well).
# - AllowPublish<service>: only the listed AWS services, and only from the listed source ARNs of this account
#   (confused deputy protection: aws:SourceAccount + aws:SourceArn).
# The default policy statement for the account owner is replaced; administration of the topic goes through IAM.
data "aws_iam_policy_document" "topic" {
  for_each = local.topics

  statement {
    sid = "DenyInsecureTransport"
    # SNS rejects the sns:* wildcard in a topic policy ("action out of service scope"), so the Deny lists the action
    # explicitly: publishing over plain HTTP is refused.
    effect    = "Deny"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.this[each.key].arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  dynamic "statement" {
    for_each = length(each.value.principal_arns) > 0 ? [1] : []

    content {
      sid       = "AllowPublishPrincipals"
      effect    = "Allow"
      actions   = ["sns:Publish"]
      resources = [aws_sns_topic.this[each.key].arn]

      principals {
        type        = "AWS"
        identifiers = each.value.principal_arns
      }

      # A role ARN of another account must not be able to publish, whatever the variable contains.
      condition {
        test     = "StringEquals"
        variable = "aws:PrincipalAccount"
        values   = [local.account_id]
      }
    }
  }

  dynamic "statement" {
    for_each = each.value.services

    content {
      sid       = "AllowPublish${replace(statement.key, "/[^A-Za-z0-9]/", "")}"
      effect    = "Allow"
      actions   = ["sns:Publish"]
      resources = [aws_sns_topic.this[each.key].arn]

      principals {
        type        = "Service"
        identifiers = [statement.key]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = statement.value
      }
    }
  }
}

resource "aws_sns_topic_policy" "this" {
  for_each = local.topics

  arn    = aws_sns_topic.this[each.key].arn
  policy = data.aws_iam_policy_document.topic[each.key].json
}

# E-mail subscriptions stay "pending confirmation" until each recipient confirms by hand.
resource "aws_sns_topic_subscription" "email" {
  for_each = local.subscription_keys

  # Keys are "<topic>-<hash>".
  topic_arn = aws_sns_topic.this[split("-", each.key)[0]].arn
  protocol  = "email"
  endpoint  = local.subscription_endpoints[each.key]
}

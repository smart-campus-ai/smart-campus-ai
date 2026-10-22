# Statement to merge into the policy of the SNS topic owned by the notifications module. This module never attaches it:
# it does not own the topic (independent bricks).
data "aws_iam_policy_document" "topic_publish" {
  count = var.sns_topic_arn == null ? 0 : 1

  statement {
    sid       = "AllowBudgetsAndCostAnomalyPublish"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [var.sns_topic_arn]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com", "costalerts.amazonaws.com"]
    }

    # Confused deputy protection: only services acting for this account.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

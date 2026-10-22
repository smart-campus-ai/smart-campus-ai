data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  budget_name          = "${var.name_prefix}-monthly"
  anomaly_monitor_name = "${var.name_prefix}-anomaly-monitor"
  anomaly_sub_name     = "${var.name_prefix}-anomaly-alerts"

  # Cost filter on the cost allocation tag: the API expects "user:<key>$<value>".
  cost_filters = var.project_tag_value == null ? {} : {
    TagKeyValue = [format("user:%s$%s", var.project_tag_key, var.project_tag_value)]
  }

  # One notification per (type, threshold). Keys are stable strings.
  notifications = merge(
    { for t in var.forecasted_thresholds_percent : "FORECASTED-${t}" => { type = "FORECASTED", threshold = t } },
    { for t in var.actual_thresholds_percent : "ACTUAL-${t}" => { type = "ACTUAL", threshold = t } },
  )

  sns_topic_arns = var.sns_topic_arn == null ? [] : [var.sns_topic_arn]
}

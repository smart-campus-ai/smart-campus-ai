resource "aws_budgets_budget" "monthly" {
  name         = local.budget_name
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = tostring(var.monthly_limit_usd)
  limit_unit   = "USD"

  dynamic "cost_filter" {
    for_each = local.cost_filters

    content {
      name   = cost_filter.key
      values = cost_filter.value
    }
  }

  dynamic "notification" {
    for_each = local.notifications

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.type
      subscriber_email_addresses = var.notification_emails
      subscriber_sns_topic_arns  = local.sns_topic_arns
    }
  }

  tags = merge(var.tags, { Name = local.budget_name })
}

resource "aws_ce_anomaly_monitor" "this" {
  count = var.enable_anomaly_detection ? 1 : 0

  name              = local.anomaly_monitor_name
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"

  tags = merge(var.tags, { Name = local.anomaly_monitor_name })
}

resource "aws_ce_anomaly_subscription" "this" {
  count = var.enable_anomaly_detection ? 1 : 0

  name             = local.anomaly_sub_name
  frequency        = "IMMEDIATE" # SNS subscribers only support immediate alerts.
  monitor_arn_list = [aws_ce_anomaly_monitor.this[0].arn]

  subscriber {
    type    = "SNS"
    address = var.sns_topic_arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_threshold_usd)]
    }
  }

  tags = merge(var.tags, { Name = local.anomaly_sub_name })
}

mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.topic_publish
    values = {
      json = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Sid       = "AllowBudgetsAndCostAnomalyPublish"
          Effect    = "Allow"
          Action    = ["SNS:Publish"]
          Resource  = ["arn:aws:sns:eu-west-3:123456789012:sc-dev-ops-alerts"]
          Principal = {
            Service = ["budgets.amazonaws.com", "costalerts.amazonaws.com"]
          }
          Condition = {
            StringEquals = {
              "aws:SourceAccount" = "123456789012"
            }
          }
        }]
      })
    }
  }

  # Computed ARN consumed by the anomaly subscription.
  override_resource {
    target = aws_ce_anomaly_monitor.this
    values = {
      arn = "arn:aws:ce::123456789012:anomalymonitor/00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  name_prefix       = "sc-dev"
  monthly_limit_usd = 50
  sns_topic_arn     = "arn:aws:sns:eu-west-3:123456789012:sc-dev-ops-alerts"
}

# EN16-AC1: monthly COST budget in USD
run "en16_ac1_monthly_cost_budget" {
  command = plan

  assert {
    condition     = aws_budgets_budget.monthly.name == "sc-dev-monthly"
    error_message = "The budget name must be <name_prefix>-monthly."
  }

  assert {
    condition     = aws_budgets_budget.monthly.budget_type == "COST" && aws_budgets_budget.monthly.time_unit == "MONTHLY"
    error_message = "The budget must be a monthly COST budget."
  }

  assert {
    condition     = aws_budgets_budget.monthly.limit_amount == "50" && aws_budgets_budget.monthly.limit_unit == "USD"
    error_message = "The limit must follow monthly_limit_usd, in USD."
  }

  assert {
    condition     = length(aws_budgets_budget.monthly.cost_filter) == 0
    error_message = "Without project_tag_value the budget must not be filtered."
  }
}

# EN16-AC1: filtered on the Project tag when a value is given
run "en16_ac1_project_tag_filter" {
  command = plan

  variables {
    project_tag_value = "smartcampus"
  }

  assert {
    condition     = length(aws_budgets_budget.monthly.cost_filter) == 1
    error_message = "Exactly one cost filter must be set."
  }

  assert {
    condition = (
      one([for f in aws_budgets_budget.monthly.cost_filter : f.name]) == "TagKeyValue" &&
      one([for f in aws_budgets_budget.monthly.cost_filter : tolist(f.values)[0]]) == "user:Project$smartcampus"
    )
    error_message = "The filter must target the cost allocation tag user:Project$<value>."
  }
}

# EN16-AC1: decimal limit is kept as is
run "en16_ac1_decimal_limit" {
  command = plan

  variables {
    monthly_limit_usd = 12.5
  }

  assert {
    condition     = aws_budgets_budget.monthly.limit_amount == "12.5"
    error_message = "A decimal limit must be kept."
  }
}

# EN16-AC2: forecasted 80/100 % and actual 100 % by default
run "en16_ac2_default_thresholds" {
  command = plan

  assert {
    condition     = length(aws_budgets_budget.monthly.notification) == 3
    error_message = "Three notifications are expected by default."
  }

  assert {
    condition     = toset([for n in aws_budgets_budget.monthly.notification : "${n.notification_type}-${n.threshold}"]) == toset(["FORECASTED-80", "FORECASTED-100", "ACTUAL-100"])
    error_message = "Defaults must be forecasted 80 and 100 % and actual 100 %."
  }

  assert {
    condition     = alltrue([for n in aws_budgets_budget.monthly.notification : n.threshold_type == "PERCENTAGE" && n.comparison_operator == "GREATER_THAN"])
    error_message = "Thresholds must be percentages with the GREATER_THAN operator."
  }
}

# EN16-AC2: notifications go to the SNS topic and the emails
run "en16_ac2_recipients_topic_and_emails" {
  command = plan

  variables {
    notification_emails = ["ops@example.com"]
  }

  assert {
    condition = alltrue([
      for n in aws_budgets_budget.monthly.notification :
      contains(n.subscriber_sns_topic_arns, "arn:aws:sns:eu-west-3:123456789012:sc-dev-ops-alerts") &&
      contains(n.subscriber_email_addresses, "ops@example.com")
    ])
    error_message = "Every notification must reach the SNS topic and the emails."
  }
}

# EN16-AC2: emails only, no topic
run "en16_ac2_recipients_emails_only" {
  command = plan

  variables {
    sns_topic_arn       = null
    notification_emails = ["ops@example.com"]
  }

  assert {
    condition = alltrue([
      for n in aws_budgets_budget.monthly.notification :
      length(n.subscriber_sns_topic_arns) == 0 && length(n.subscriber_email_addresses) == 1
    ])
    error_message = "Without topic, notifications must only target the emails."
  }
}

# EN16-AC2: thresholds are configurable
run "en16_ac2_custom_thresholds" {
  command = plan

  variables {
    forecasted_thresholds_percent = [50, 80, 100]
    actual_thresholds_percent     = [80, 100]
  }

  assert {
    condition = toset([for n in aws_budgets_budget.monthly.notification : "${n.notification_type}-${n.threshold}"]) == toset([
      "FORECASTED-50", "FORECASTED-80", "FORECASTED-100", "ACTUAL-80", "ACTUAL-100"
    ])
    error_message = "Thresholds must follow the variables."
  }
}

# EN16-AC2: anomaly detection is off by default
run "en16_ac2_anomaly_disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_ce_anomaly_monitor.this) == 0 && length(aws_ce_anomaly_subscription.this) == 0
    error_message = "No anomaly resource must be created by default."
  }

  assert {
    condition     = output.anomaly_monitor_arn == null && output.anomaly_subscription_arn == null
    error_message = "Anomaly outputs must be null when disabled."
  }
}

# EN16-AC2: anomaly monitor and subscription publish to the topic
run "en16_ac2_anomaly_enabled" {
  command = plan

  variables {
    enable_anomaly_detection = true
    anomaly_threshold_usd    = 25
  }

  assert {
    condition     = aws_ce_anomaly_monitor.this[0].monitor_type == "DIMENSIONAL" && aws_ce_anomaly_monitor.this[0].monitor_dimension == "SERVICE"
    error_message = "The monitor must be dimensional on SERVICE."
  }

  assert {
    condition     = aws_ce_anomaly_subscription.this[0].frequency == "IMMEDIATE"
    error_message = "An SNS subscription requires the IMMEDIATE frequency."
  }

  assert {
    condition = (
      one([for s in aws_ce_anomaly_subscription.this[0].subscriber : s.type]) == "SNS" &&
      one([for s in aws_ce_anomaly_subscription.this[0].subscriber : s.address]) == "arn:aws:sns:eu-west-3:123456789012:sc-dev-ops-alerts"
    )
    error_message = "The subscriber must be the SNS topic."
  }

  assert {
    condition = (
      one([for e in aws_ce_anomaly_subscription.this[0].threshold_expression : one([for d in e.dimension : d.key])]) == "ANOMALY_TOTAL_IMPACT_ABSOLUTE" &&
      one([for e in aws_ce_anomaly_subscription.this[0].threshold_expression : one([for d in e.dimension : tolist(d.values)[0]])]) == "25"
    )
    error_message = "The threshold expression must use the absolute impact and anomaly_threshold_usd."
  }
}

# EN16-AC2: topic policy statement allows the two billing services with a source account condition
run "en16_ac2_topic_policy_statement" {
  command = plan

  assert {
    condition     = length(jsondecode(output.topic_policy_statement_json).Statement) == 1
    error_message = "One statement is expected."
  }

  assert {
    condition = (
      one(jsondecode(output.topic_policy_statement_json).Statement).Effect == "Allow" &&
      toset(one(jsondecode(output.topic_policy_statement_json).Statement).Action) == toset(["SNS:Publish"]) &&
      toset(one(jsondecode(output.topic_policy_statement_json).Statement).Resource) == toset(["arn:aws:sns:eu-west-3:123456789012:sc-dev-ops-alerts"])
    )
    error_message = "The statement must only allow SNS:Publish on the topic (no wildcard)."
  }

  assert {
    condition = (
      one(jsondecode(output.topic_policy_statement_json).Statement).Principal.Service == toset(["budgets.amazonaws.com", "costalerts.amazonaws.com"])
    )
    error_message = "Only budgets.amazonaws.com and costalerts.amazonaws.com may publish."
  }

  assert {
    condition = (
      one(jsondecode(output.topic_policy_statement_json).Statement).Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    )
    error_message = "The statement must be restricted by aws:SourceAccount."
  }

  assert {
    condition     = output.topic_policy_statement_json != null
    error_message = "The statement JSON must be exposed."
  }
}

run "en16_ac2_topic_policy_absent_without_topic" {
  command = plan

  variables {
    sns_topic_arn       = null
    notification_emails = ["ops@example.com"]
  }

  assert {
    condition     = length(data.aws_iam_policy_document.topic_publish) == 0 && output.topic_policy_statement_json == null
    error_message = "No topic policy statement without topic."
  }
}

# EN16-AC3: nul or negative amount
run "en16_ac3_zero_limit_rejected" {
  command = plan

  variables {
    monthly_limit_usd = 0
  }

  expect_failures = [var.monthly_limit_usd]
}

run "en16_ac3_negative_limit_rejected" {
  command = plan

  variables {
    monthly_limit_usd = -10
  }

  expect_failures = [var.monthly_limit_usd]
}

run "en16_ac3_no_recipient_rejected" {
  command = plan

  variables {
    sns_topic_arn       = null
    notification_emails = []
  }

  expect_failures = [var.notification_emails]
}

run "en16_ac3_invalid_email_rejected" {
  command = plan

  variables {
    notification_emails = ["not-an-email"]
  }

  expect_failures = [var.notification_emails]
}

run "en16_ac3_invalid_topic_arn_rejected" {
  command = plan

  variables {
    sns_topic_arn = "not-an-arn"
  }

  expect_failures = [var.sns_topic_arn]
}

run "en16_ac3_zero_threshold_rejected" {
  command = plan

  variables {
    actual_thresholds_percent = [0]
  }

  expect_failures = [var.actual_thresholds_percent]
}

run "en16_ac3_no_threshold_rejected" {
  command = plan

  variables {
    forecasted_thresholds_percent = []
    actual_thresholds_percent     = []
  }

  expect_failures = [var.actual_thresholds_percent]
}

run "en16_ac3_anomaly_without_topic_rejected" {
  command = plan

  variables {
    sns_topic_arn            = null
    notification_emails      = ["ops@example.com"]
    enable_anomaly_detection = true
  }

  expect_failures = [var.enable_anomaly_detection]
}

run "en16_ac3_zero_anomaly_threshold_rejected" {
  command = plan

  variables {
    anomaly_threshold_usd = 0
  }

  expect_failures = [var.anomaly_threshold_usd]
}

run "en16_ac3_invalid_name_prefix_rejected" {
  command = plan

  variables {
    name_prefix = "SC_DEV"
  }

  expect_failures = [var.name_prefix]
}

mock_provider "aws" {
  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-1"
    }
  }
}

variables {
  name_prefix = "sc-dev"
  # Documentation account ID and placeholder names.
  alarm_topic_arn = "arn:aws:sns:us-east-1:123456789012:sc-dev-ops"

  api = {
    name       = "sc-dev-api"
    stage_name = "live"
  }

  lambda_function_names        = ["sc-dev-tickets", "sc-dev-chat"]
  dynamodb_table_names         = ["sc-dev-tickets"]
  dlq_queue_names              = ["sc-dev-tickets-dlq", "sc-dev-notifier-dlq"]
  waf_regional_web_acl_names   = ["sc-dev-api"]
  cloudfront_waf_web_acl_names = ["sc-dev-edge"]

  auth_failure_log_group_name = "/aws/apigateway/sc-dev-api-access"

  log_metric_filters = {
    "tickets-timeouts" = {
      log_group_name  = "/aws/lambda/sc-dev-tickets"
      pattern         = "\"Task timed out\""
      alarm_threshold = 3
    }
    "chat-fallbacks" = {
      log_group_name = "/aws/lambda/sc-dev-chat"
      pattern        = "{ $.event = \"assistant_fallback\" }"
    }
  }
}

# EN61-AC1: metric filters attach to the log groups given by the producers, in the module namespace
run "en61_ac1_metric_filters_target_given_log_groups" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_metric_filter.this["auth-failures"].log_group_name == "/aws/apigateway/sc-dev-api-access"
    error_message = "The authentication filter must target auth_failure_log_group_name."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.this["tickets-timeouts"].log_group_name == "/aws/lambda/sc-dev-tickets"
    error_message = "A custom filter must target its own log group."
  }

  assert {
    condition = alltrue([
      for f in aws_cloudwatch_log_metric_filter.this : one(f.metric_transformation).namespace == "sc-dev/Logs"
    ])
    error_message = "Every filter metric must be published in the <prefix>/Logs namespace."
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.this) == 3
    error_message = "Expected the authentication filter and the two custom filters."
  }
}

# EN61-AC3: the dashboard shows requests, 4xx/5xx, p95 latency, Lambda errors and throttles, DLQ depth and WAF blocks
run "en61_ac3_dashboard_covers_required_signals" {
  command = plan

  assert {
    condition = alltrue([
      for t in [
        "API requests", "API 4XX / 5XX", "API latency p95", "Lambda errors", "Lambda throttles", "DLQ depth",
        "WAF blocked requests", "DynamoDB consumed capacity", "DynamoDB throttle events",
      ] :
      contains([for w in jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets : w.properties.title], t)
    ])
    error_message = "The dashboard must contain the requests, 4XX/5XX, latency p95, Lambda, DynamoDB, DLQ and WAF widgets."
  }

  assert {
    condition     = aws_cloudwatch_dashboard.this.dashboard_name == "sc-dev-overview"
    error_message = "The dashboard must be named <prefix>-overview."
  }
}

# EN61-AC3: the dashboard is built from the given names
run "en61_ac3_dashboard_is_built_from_inputs" {
  command = plan

  assert {
    condition = toset([
      for m in one([for w in jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets : w if w.properties.title == "Lambda errors"]).properties.metrics : m[3]
    ]) == toset(["sc-dev-tickets", "sc-dev-chat"])
    error_message = "The Lambda errors widget must list exactly the given functions."
  }

  assert {
    condition = toset([
      for m in one([for w in jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets : w if w.properties.title == "DLQ depth"]).properties.metrics : m[3]
    ]) == toset(["sc-dev-tickets-dlq", "sc-dev-notifier-dlq"])
    error_message = "The DLQ widget must list exactly the given queues."
  }

  assert {
    condition = alltrue([
      for m in one([for w in jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets : w if w.properties.title == "API latency p95"]).properties.metrics :
      m[3] == "sc-dev-api" && m[5] == "live"
    ])
    error_message = "The API widgets must use the given API name and stage."
  }

  assert {
    condition = anytrue([
      for m in one([for w in jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets : w if w.properties.title == "WAF blocked requests"]).properties.metrics :
      m[3] == "sc-dev-edge" && m[7] == "Global" && m[8].region == "us-east-1"
      if length(m) == 9
    ])
    error_message = "The CloudFront web ACL must be read in us-east-1 with the Global region dimension."
  }

  assert {
    condition = alltrue([
      for w in jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets : w.width == 12 && w.height == 6
    ])
    error_message = "Every widget must have an explicit size."
  }
}

# EN61-AC3: widgets without an observed input are left out
run "en61_ac3_dashboard_skips_widgets_without_inputs" {
  command = plan

  variables {
    api                          = null
    lambda_function_names        = []
    dynamodb_table_names         = []
    dlq_queue_names              = []
    waf_regional_web_acl_names   = []
    cloudfront_waf_web_acl_names = []
    auth_failure_log_group_name  = null
    log_metric_filters           = {}
  }

  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets) == 0
    error_message = "No widget must be rendered when nothing is observed."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.api_5xx_rate) + length(aws_cloudwatch_metric_alarm.api_latency_p95) == 0
    error_message = "No API alarm must be created without api."
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.this) == 0
    error_message = "No metric filter must be created without log groups."
  }
}

# EN61-AC4: a dedicated metric filter counts 401/403 and the dashboard shows it
run "en61_ac4_auth_failure_metric_filter" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_metric_filter.this["auth-failures"].pattern == "{ ($.status = 401) || ($.status = 403) }"
    error_message = "The authentication filter must count 401 and 403 responses."
  }

  assert {
    condition     = one(aws_cloudwatch_log_metric_filter.this["auth-failures"].metric_transformation).name == "auth-failures"
    error_message = "The authentication metric must be named auth-failures."
  }

  assert {
    condition     = contains([for w in jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets : w.properties.title], "API authentication failures (401/403)")
    error_message = "The dashboard must show the authentication failures."
  }
}

# EN61-AC4: an alarm fires on an authentication failure spike
run "en61_ac4_auth_failure_alarm" {
  command = plan

  variables {
    auth_failure_threshold = 20
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.log_metric_filter["auth-failures"].threshold == 20
    error_message = "The authentication alarm must follow auth_failure_threshold."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.log_metric_filter["auth-failures"].metric_name == "auth-failures" && aws_cloudwatch_metric_alarm.log_metric_filter["auth-failures"].namespace == "sc-dev/Logs"
    error_message = "The authentication alarm must watch the filter metric."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.log_metric_filter["auth-failures"].comparison_operator == "GreaterThanOrEqualToThreshold"
    error_message = "The authentication alarm must fire when the threshold is reached."
  }
}

# EN61-AC4: the authentication filter is optional
run "en61_ac4_auth_failure_filter_is_optional" {
  command = plan

  variables {
    auth_failure_log_group_name = null
  }

  assert {
    condition     = !contains(keys(aws_cloudwatch_log_metric_filter.this), "auth-failures") && !contains(keys(aws_cloudwatch_metric_alarm.log_metric_filter), "auth-failures")
    error_message = "Without auth_failure_log_group_name there must be no authentication filter or alarm."
  }
}

# EN61-AC4: a custom filter only gets an alarm when it has a threshold
run "en61_ac4_custom_filter_alarm_only_with_threshold" {
  command = plan

  assert {
    condition     = contains(keys(aws_cloudwatch_metric_alarm.log_metric_filter), "tickets-timeouts") && !contains(keys(aws_cloudwatch_metric_alarm.log_metric_filter), "chat-fallbacks")
    error_message = "Only the filter with alarm_threshold must have an alarm."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.log_metric_filter["tickets-timeouts"].threshold == 3
    error_message = "The custom alarm must use the filter alarm_threshold."
  }
}

# EN61-AC5: the API 5xx rate alarm computes a rate guarded by a minimum request count
run "en61_ac5_api_5xx_rate_alarm" {
  command = plan

  variables {
    api_5xx_rate_threshold_percent = 2
    api_5xx_min_requests           = 20
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.api_5xx_rate[0].threshold == 2 && aws_cloudwatch_metric_alarm.api_5xx_rate[0].comparison_operator == "GreaterThanThreshold"
    error_message = "The 5xx alarm must fire above api_5xx_rate_threshold_percent."
  }

  assert {
    condition     = one([for q in aws_cloudwatch_metric_alarm.api_5xx_rate[0].metric_query : q if q.id == "rate"]).return_data == true
    error_message = "Only the rate expression must be evaluated by the alarm."
  }

  assert {
    condition     = strcontains(one([for q in aws_cloudwatch_metric_alarm.api_5xx_rate[0].metric_query : q if q.id == "rate"]).expression, "mcount >= 20")
    error_message = "The rate must be guarded by api_5xx_min_requests."
  }

  assert {
    condition = toset([
      for q in aws_cloudwatch_metric_alarm.api_5xx_rate[0].metric_query : one(q.metric).metric_name if q.id != "rate"
    ]) == toset(["5XXError", "Count"])
    error_message = "The rate must be computed from 5XXError and Count."
  }

  assert {
    condition = alltrue([
      for q in aws_cloudwatch_metric_alarm.api_5xx_rate[0].metric_query :
      one(q.metric).namespace == "AWS/ApiGateway" && one(q.metric).dimensions["ApiName"] == "sc-dev-api" && one(q.metric).dimensions["Stage"] == "live"
      if q.id != "rate"
    ])
    error_message = "The 5xx and request count metrics must use the API name and stage."
  }
}

# EN61-AC5: the API p95 latency alarm defaults to the 2000 ms NFR
run "en61_ac5_api_latency_p95_alarm" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.api_latency_p95[0].extended_statistic == "p95" && aws_cloudwatch_metric_alarm.api_latency_p95[0].metric_name == "Latency"
    error_message = "The latency alarm must watch the p95 of Latency."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.api_latency_p95[0].threshold == 2000 && aws_cloudwatch_metric_alarm.api_latency_p95[0].comparison_operator == "GreaterThanThreshold"
    error_message = "The latency alarm must fire above 2000 ms by default."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.api_latency_p95[0].dimensions == tomap({ ApiName = "sc-dev-api", Stage = "live" })
    error_message = "The latency alarm must use the API name and stage."
  }
}

# EN61-AC5: each Lambda function gets an errors alarm and a throttles alarm
run "en61_ac5_lambda_alarms_per_function" {
  command = plan

  variables {
    lambda_errors_threshold    = 2
    lambda_throttles_threshold = 1
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_metric_alarm.lambda_errors)) == toset(["sc-dev-tickets", "sc-dev-chat"]) && toset(keys(aws_cloudwatch_metric_alarm.lambda_throttles)) == toset(["sc-dev-tickets", "sc-dev-chat"])
    error_message = "Every function must have an errors alarm and a throttles alarm."
  }

  assert {
    condition = alltrue([
      for a in aws_cloudwatch_metric_alarm.lambda_errors :
      a.metric_name == "Errors" && a.namespace == "AWS/Lambda" && a.statistic == "Sum" && a.threshold == 2 && a.evaluation_periods == 1
    ])
    error_message = "Lambda errors alarms must sum Errors above lambda_errors_threshold over one period."
  }

  assert {
    condition = alltrue([
      for a in aws_cloudwatch_metric_alarm.lambda_throttles :
      a.metric_name == "Throttles" && a.namespace == "AWS/Lambda" && a.statistic == "Sum" && a.threshold == 1 && a.evaluation_periods == 1
    ])
    error_message = "Lambda throttles alarms must sum Throttles above lambda_throttles_threshold over one period."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_errors["sc-dev-chat"].dimensions == tomap({ FunctionName = "sc-dev-chat" })
    error_message = "Lambda alarms must use the FunctionName dimension."
  }
}

# EN61-AC5: each DLQ gets a depth alarm that fires on any message by default
run "en61_ac5_dlq_depth_alarm" {
  command = plan

  assert {
    condition     = toset(keys(aws_cloudwatch_metric_alarm.dlq_depth)) == toset(["sc-dev-tickets-dlq", "sc-dev-notifier-dlq"])
    error_message = "Every DLQ must have a depth alarm."
  }

  assert {
    condition = alltrue([
      for a in aws_cloudwatch_metric_alarm.dlq_depth :
      a.namespace == "AWS/SQS" && a.metric_name == "ApproximateNumberOfMessagesVisible" && a.statistic == "Maximum" && a.threshold == 0 && a.comparison_operator == "GreaterThanThreshold"
    ])
    error_message = "DLQ alarms must fire when the visible message count is above 0."
  }
}

# EN61-AC5: regional web ACLs get a blocked-requests alarm
run "en61_ac5_waf_blocked_requests_alarm" {
  command = plan

  variables {
    waf_blocked_requests_threshold = 500
  }

  assert {
    condition     = keys(aws_cloudwatch_metric_alarm.waf_blocked_requests) == ["sc-dev-api"]
    error_message = "Only the regional web ACL must have an alarm."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.waf_blocked_requests["sc-dev-api"].threshold == 500 && aws_cloudwatch_metric_alarm.waf_blocked_requests["sc-dev-api"].metric_name == "BlockedRequests"
    error_message = "The WAF alarm must follow waf_blocked_requests_threshold."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.waf_blocked_requests["sc-dev-api"].dimensions == tomap({ WebACL = "sc-dev-api", Rule = "ALL", Region = "us-east-1" })
    error_message = "The regional WAF alarm must use the WebACL, Rule and Region dimensions."
  }
}

# EN61-AC5: CloudFront-scope web ACLs get a blocked-requests alarm in us-east-1 with Region=Global
run "en61_ac5_cloudfront_waf_blocked_requests_alarm" {
  command = plan

  variables {
    waf_blocked_requests_threshold = 200
  }

  assert {
    condition     = keys(aws_cloudwatch_metric_alarm.cloudfront_waf_blocked_requests) == ["sc-dev-edge"]
    error_message = "Only the CloudFront web ACL must have an alarm."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cloudfront_waf_blocked_requests["sc-dev-edge"].threshold == 200 && aws_cloudwatch_metric_alarm.cloudfront_waf_blocked_requests["sc-dev-edge"].metric_name == "BlockedRequests"
    error_message = "The CloudFront WAF alarm must follow waf_blocked_requests_threshold."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cloudfront_waf_blocked_requests["sc-dev-edge"].dimensions == tomap({ WebACL = "sc-dev-edge", Rule = "ALL", Region = "Global" })
    error_message = "The CloudFront WAF alarm must use Region=Global dimension."
  }
}

# EN61-AC5: every alarm publishes to the ops topic and treats missing data as healthy
run "en61_ac5_alarms_publish_to_ops_topic" {
  command = plan

  assert {
    condition = alltrue(concat(
      [for a in aws_cloudwatch_metric_alarm.api_5xx_rate : a.alarm_actions == toset(["arn:aws:sns:us-east-1:123456789012:sc-dev-ops"])],
      [for a in aws_cloudwatch_metric_alarm.api_latency_p95 : a.alarm_actions == toset(["arn:aws:sns:us-east-1:123456789012:sc-dev-ops"])],
      [for a in aws_cloudwatch_metric_alarm.lambda_errors : a.alarm_actions == toset(["arn:aws:sns:us-east-1:123456789012:sc-dev-ops"])],
      [for a in aws_cloudwatch_metric_alarm.lambda_throttles : a.alarm_actions == toset(["arn:aws:sns:us-east-1:123456789012:sc-dev-ops"])],
      [for a in aws_cloudwatch_metric_alarm.dlq_depth : a.alarm_actions == toset(["arn:aws:sns:us-east-1:123456789012:sc-dev-ops"])],
      [for a in aws_cloudwatch_metric_alarm.waf_blocked_requests : a.alarm_actions == toset(["arn:aws:sns:us-east-1:123456789012:sc-dev-ops"])],
      [for a in aws_cloudwatch_metric_alarm.cloudfront_waf_blocked_requests : a.alarm_actions == toset(["arn:aws:sns:us-east-1:123456789012:sc-dev-ops"])],
      [for a in aws_cloudwatch_metric_alarm.log_metric_filter : a.alarm_actions == toset(["arn:aws:sns:us-east-1:123456789012:sc-dev-ops"])],
    ))
    error_message = "Every alarm must publish to alarm_topic_arn."
  }

  assert {
    condition = alltrue(concat(
      [for a in aws_cloudwatch_metric_alarm.api_5xx_rate : a.treat_missing_data == "notBreaching"],
      [for a in aws_cloudwatch_metric_alarm.api_latency_p95 : a.treat_missing_data == "notBreaching"],
      [for a in aws_cloudwatch_metric_alarm.lambda_errors : a.treat_missing_data == "notBreaching"],
      [for a in aws_cloudwatch_metric_alarm.lambda_throttles : a.treat_missing_data == "notBreaching"],
      [for a in aws_cloudwatch_metric_alarm.dlq_depth : a.treat_missing_data == "notBreaching"],
      [for a in aws_cloudwatch_metric_alarm.waf_blocked_requests : a.treat_missing_data == "notBreaching"],
      [for a in aws_cloudwatch_metric_alarm.cloudfront_waf_blocked_requests : a.treat_missing_data == "notBreaching"],
      [for a in aws_cloudwatch_metric_alarm.log_metric_filter : a.treat_missing_data == "notBreaching"],
    ))
    error_message = "Missing data must not breach, so that an idle environment does not page."
  }
}

# EN61-AC5: rate-based alarms follow the evaluation settings
run "en61_ac5_rate_alarms_follow_evaluation_settings" {
  command = plan

  variables {
    alarm_period_seconds      = 60
    alarm_evaluation_periods  = 5
    alarm_datapoints_to_alarm = 3
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.api_latency_p95[0].period == 60 &&
      aws_cloudwatch_metric_alarm.api_latency_p95[0].evaluation_periods == 5 &&
      aws_cloudwatch_metric_alarm.api_latency_p95[0].datapoints_to_alarm == 3
    )
    error_message = "The latency alarm must follow the period and evaluation variables."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.api_5xx_rate[0].evaluation_periods == 5 &&
      aws_cloudwatch_metric_alarm.api_5xx_rate[0].datapoints_to_alarm == 3 &&
      alltrue([for q in aws_cloudwatch_metric_alarm.api_5xx_rate[0].metric_query : one(q.metric).period == 60 if q.id != "rate"])
    )
    error_message = "The 5xx alarm must follow the period and evaluation variables, on every underlying metric."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.dlq_depth["sc-dev-tickets-dlq"].datapoints_to_alarm == 1 && aws_cloudwatch_metric_alarm.dlq_depth["sc-dev-tickets-dlq"].period == 60
    error_message = "DLQ alarms must evaluate a single breaching period."
  }
}

# EN61-AC6: filters count events without extracting log content
run "en61_ac6_metric_filters_extract_no_log_content" {
  command = plan

  assert {
    condition = alltrue([
      for f in aws_cloudwatch_log_metric_filter.this :
      one(f.metric_transformation).value == "1" && length(coalesce(one(f.metric_transformation).dimensions, {})) == 0
    ])
    error_message = "Metric filters must publish a constant value of 1 without dimensions, so no log content leaks into metrics."
  }
}

# EN61-AC5: outputs expose the dashboard and the metric namespace
run "en61_ac5_outputs_expose_dashboard_and_namespace" {
  command = plan

  assert {
    condition     = output.metric_namespace == "sc-dev/Logs" && output.dashboard_name == "sc-dev-overview"
    error_message = "Outputs must expose the dashboard name and the metric namespace."
  }
}

# EN61-AC5: rejects an invalid SNS topic ARN
run "en61_ac5_rejects_invalid_topic_arn" {
  command = plan

  variables {
    alarm_topic_arn = "sc-dev-ops"
  }

  expect_failures = [var.alarm_topic_arn]
}

# EN61-AC5: rejects an alarm period that is not a multiple of 60
run "en61_ac5_rejects_period_not_multiple_of_60" {
  command = plan

  variables {
    alarm_period_seconds = 90
  }

  expect_failures = [var.alarm_period_seconds]
}

# EN61-AC5: rejects more datapoints than evaluation periods
run "en61_ac5_rejects_datapoints_above_evaluation_periods" {
  command = plan

  variables {
    alarm_evaluation_periods  = 2
    alarm_datapoints_to_alarm = 3
  }

  expect_failures = [var.alarm_datapoints_to_alarm]
}

# EN61-AC5: rejects a 5xx rate threshold above 100 percent
run "en61_ac5_rejects_5xx_threshold_above_100" {
  command = plan

  variables {
    api_5xx_rate_threshold_percent = 101
  }

  expect_failures = [var.api_5xx_rate_threshold_percent]
}

# EN61-AC5: rejects a negative DLQ threshold
run "en61_ac5_rejects_negative_dlq_threshold" {
  command = plan

  variables {
    dlq_depth_threshold = -1
  }

  expect_failures = [var.dlq_depth_threshold]
}

# EN61-AC5: rejects a Lambda ARN where a function name is expected
run "en61_ac5_rejects_lambda_arn_as_name" {
  command = plan

  variables {
    lambda_function_names = ["arn:aws:lambda:us-east-1:123456789012:function:sc-dev-tickets"]
  }

  expect_failures = [var.lambda_function_names]
}

# EN61-AC5: rejects a queue URL where a queue name is expected
run "en61_ac5_rejects_queue_url_as_name" {
  command = plan

  variables {
    dlq_queue_names = ["https://sqs.us-east-1.amazonaws.com/123456789012/sc-dev-dlq"]
  }

  expect_failures = [var.dlq_queue_names]
}

# EN61-AC1: rejects an invalid name_prefix
run "en61_ac1_rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Bad_Prefix"
  }

  expect_failures = [var.name_prefix]
}

# EN61-AC4: rejects a custom filter that uses the reserved authentication key
run "en61_ac4_rejects_reserved_filter_key" {
  command = plan

  variables {
    log_metric_filters = {
      "auth-failures" = {
        log_group_name = "/aws/lambda/sc-dev-tickets"
        pattern        = "ERROR"
      }
    }
  }

  expect_failures = [var.log_metric_filters]
}

# EN61-AC4: rejects a custom filter alarm threshold below 1
run "en61_ac4_rejects_filter_threshold_below_1" {
  command = plan

  variables {
    log_metric_filters = {
      "tickets-errors" = {
        log_group_name  = "/aws/lambda/sc-dev-tickets"
        pattern         = "ERROR"
        alarm_threshold = 0
      }
    }
  }

  expect_failures = [var.log_metric_filters]
}

# EN61-AC4: rejects an invalid authentication log group name
run "en61_ac4_rejects_invalid_auth_log_group_name" {
  command = plan

  variables {
    auth_failure_log_group_name = "not a log group"
  }

  expect_failures = [var.auth_failure_log_group_name]
}

# EN61-AC3: rejects an API stage name with invalid characters
run "en61_ac3_rejects_invalid_api_stage_name" {
  command = plan

  variables {
    api = {
      name       = "sc-dev-api"
      stage_name = "live/v1"
    }
  }

  expect_failures = [var.api]
}

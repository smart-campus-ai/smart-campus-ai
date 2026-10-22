# Every alarm publishes to the ops SNS topic when it goes into ALARM. Missing data is not breaching: an idle
# environment (no traffic, no errors) must not page.

# ---------------------------------------------------------------------------
# API Gateway
# ---------------------------------------------------------------------------

# 5xx rate in percent of requests. The denominator is the request count, so that the alarm follows traffic;
# below api_5xx_min_requests the rate is 0.
resource "aws_cloudwatch_metric_alarm" "api_5xx_rate" {
  count = var.api == null ? 0 : 1

  alarm_name          = "${var.name_prefix}-api-5xx-rate"
  alarm_description   = "API ${try(var.api.name, "")} stage ${try(var.api.stage_name, "")}: 5xx rate above ${var.api_5xx_rate_threshold_percent}% of requests."
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.api_5xx_rate_threshold_percent
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  tags                = var.tags

  metric_query {
    id          = "rate"
    expression  = "IF(mcount >= ${var.api_5xx_min_requests}, 100 * FILL(m5xx, 0) / mcount, 0)"
    label       = "5XX rate (%)"
    return_data = true
  }

  metric_query {
    id = "m5xx"

    metric {
      namespace   = "AWS/ApiGateway"
      metric_name = "5XXError"
      period      = var.alarm_period_seconds
      stat        = "Sum"
      dimensions = {
        ApiName = try(var.api.name, "")
        Stage   = try(var.api.stage_name, "")
      }
    }
  }

  metric_query {
    id = "mcount"

    metric {
      namespace   = "AWS/ApiGateway"
      metric_name = "Count"
      period      = var.alarm_period_seconds
      stat        = "Sum"
      dimensions = {
        ApiName = try(var.api.name, "")
        Stage   = try(var.api.stage_name, "")
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "api_latency_p95" {
  count = var.api == null ? 0 : 1

  alarm_name          = "${var.name_prefix}-api-latency-p95"
  alarm_description   = "API ${try(var.api.name, "")} stage ${try(var.api.stage_name, "")}: p95 latency above ${var.api_latency_p95_threshold_ms} ms."
  namespace           = "AWS/ApiGateway"
  metric_name         = "Latency"
  extended_statistic  = "p95"
  period              = var.alarm_period_seconds
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.api_latency_p95_threshold_ms
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  tags                = var.tags

  dimensions = {
    ApiName = try(var.api.name, "")
    Stage   = try(var.api.stage_name, "")
  }
}

# ---------------------------------------------------------------------------
# Lambda
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = var.lambda_function_names

  alarm_name          = "${var.name_prefix}-lambda-errors-${each.key}"
  alarm_description   = "Lambda ${each.key}: more than ${var.lambda_errors_threshold} errors in ${var.alarm_period_seconds} seconds."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = var.alarm_period_seconds
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.lambda_errors_threshold
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  tags                = var.tags

  dimensions = {
    FunctionName = each.key
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = var.lambda_function_names

  alarm_name          = "${var.name_prefix}-lambda-throttles-${each.key}"
  alarm_description   = "Lambda ${each.key}: more than ${var.lambda_throttles_threshold} throttles in ${var.alarm_period_seconds} seconds."
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  period              = var.alarm_period_seconds
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.lambda_throttles_threshold
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  tags                = var.tags

  dimensions = {
    FunctionName = each.key
  }
}

# ---------------------------------------------------------------------------
# SQS dead-letter queues
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  for_each = var.dlq_queue_names

  alarm_name          = "${var.name_prefix}-dlq-depth-${each.key}"
  alarm_description   = "DLQ ${each.key}: more than ${var.dlq_depth_threshold} visible messages. A failed event is waiting for investigation."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = var.alarm_period_seconds
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.dlq_depth_threshold
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  tags                = var.tags

  dimensions = {
    QueueName = each.key
  }
}

# ---------------------------------------------------------------------------
# WAF (REGIONAL and CLOUDFRONT scope)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "waf_blocked_requests" {
  for_each = var.waf_regional_web_acl_names

  alarm_name          = "${var.name_prefix}-waf-blocked-${each.key}"
  alarm_description   = "Web ACL ${each.key}: more than ${var.waf_blocked_requests_threshold} blocked requests in ${var.alarm_period_seconds} seconds."
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  statistic           = "Sum"
  period              = var.alarm_period_seconds
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.waf_blocked_requests_threshold
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  tags                = var.tags

  dimensions = {
    WebACL = each.key
    Rule   = "ALL"
    Region = local.region
  }
}

# CloudFront-scope WAF alarms. Metrics are published in us-east-1 with Region=Global.
# The provider must have a us-east-1 alias for these alarms.
resource "aws_cloudwatch_metric_alarm" "cloudfront_waf_blocked_requests" {
  for_each = var.cloudfront_waf_web_acl_names

  provider = aws.us_east_1

  alarm_name          = "${var.name_prefix}-cloudfront-waf-blocked-${each.key}"
  alarm_description   = "CloudFront Web ACL ${each.key}: more than ${var.waf_blocked_requests_threshold} blocked requests in ${var.alarm_period_seconds} seconds."
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  statistic           = "Sum"
  period              = var.alarm_period_seconds
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.waf_blocked_requests_threshold
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  tags                = var.tags

  dimensions = {
    WebACL = each.key
    Rule   = "ALL"
    Region = local.cloudfront_waf_dimension_region
  }
}

# ---------------------------------------------------------------------------
# Log metric filters (authentication failures and caller-defined filters with a threshold)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "log_metric_filter" {
  for_each = local.alarmed_metric_filters

  alarm_name          = "${var.name_prefix}-logs-${each.key}"
  alarm_description   = "Log metric ${each.key}: ${each.value.alarm_threshold} or more matching events in ${var.alarm_period_seconds} seconds."
  namespace           = local.metric_namespace
  metric_name         = each.key
  statistic           = "Sum"
  period              = var.alarm_period_seconds
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = each.value.alarm_threshold
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  tags                = var.tags
}

locals {
  dashboard_period = 300

  api_dimensions = ["ApiName", try(var.api.name, ""), "Stage", try(var.api.stage_name, "")]

  # Candidate widgets in display order. A widget is kept only when the input it observes is not empty.
  # Metric rows: [namespace, metric, dimension name, dimension value, ..., {options}].
  widget_candidates = [
    {
      enabled = var.api != null
      widget = {
        type = "metric"
        properties = {
          title   = "API requests"
          view    = "timeSeries"
          stacked = false
          region  = local.region
          period  = local.dashboard_period
          stat    = "Sum"
          metrics = [
            concat(["AWS/ApiGateway", "Count"], local.api_dimensions, [{ label = "Requests" }]),
          ]
        }
      }
    },
    {
      enabled = var.api != null
      widget = {
        type = "metric"
        properties = {
          title   = "API 4XX / 5XX"
          view    = "timeSeries"
          stacked = false
          region  = local.region
          period  = local.dashboard_period
          stat    = "Sum"
          metrics = [
            concat(["AWS/ApiGateway", "4XXError"], local.api_dimensions, [{ label = "4XX" }]),
            concat(["AWS/ApiGateway", "5XXError"], local.api_dimensions, [{ label = "5XX" }]),
          ]
        }
      }
    },
    {
      enabled = var.api != null
      widget = {
        type = "metric"
        properties = {
          title   = "API latency p95"
          view    = "timeSeries"
          stacked = false
          region  = local.region
          period  = local.dashboard_period
          stat    = "p95"
          metrics = [
            concat(["AWS/ApiGateway", "Latency"], local.api_dimensions, [{ label = "Latency p95" }]),
            concat(["AWS/ApiGateway", "IntegrationLatency"], local.api_dimensions, [{ label = "Integration latency p95" }]),
          ]
          annotations = {
            horizontal = [{ label = "Threshold", value = var.api_latency_p95_threshold_ms }]
          }
        }
      }
    },
    {
      enabled = var.auth_failure_log_group_name != null
      widget = {
        type = "metric"
        properties = {
          title   = "API authentication failures (401/403)"
          view    = "timeSeries"
          stacked = false
          region  = local.region
          period  = local.dashboard_period
          stat    = "Sum"
          metrics = [
            [local.metric_namespace, "auth-failures", { label = "401/403" }],
          ]
        }
      }
    },
    {
      enabled = length(var.lambda_function_names) > 0
      widget = {
        type = "metric"
        properties = {
          title   = "Lambda errors"
          view    = "timeSeries"
          stacked = false
          region  = local.region
          period  = local.dashboard_period
          stat    = "Sum"
          metrics = [for f in var.lambda_function_names : ["AWS/Lambda", "Errors", "FunctionName", f]]
        }
      }
    },
    {
      enabled = length(var.lambda_function_names) > 0
      widget = {
        type = "metric"
        properties = {
          title   = "Lambda throttles"
          view    = "timeSeries"
          stacked = false
          region  = local.region
          period  = local.dashboard_period
          stat    = "Sum"
          metrics = [for f in var.lambda_function_names : ["AWS/Lambda", "Throttles", "FunctionName", f]]
        }
      }
    },
    {
      enabled = length(var.dlq_queue_names) > 0
      widget = {
        type = "metric"
        properties = {
          title   = "DLQ depth"
          view    = "timeSeries"
          stacked = false
          region  = local.region
          period  = local.dashboard_period
          stat    = "Maximum"
          metrics = [for q in var.dlq_queue_names : ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", q]]
        }
      }
    },
    {
      enabled = length(var.waf_regional_web_acl_names) + length(var.cloudfront_waf_web_acl_names) > 0
      widget = {
        type = "metric"
        properties = {
          title   = "WAF blocked requests"
          view    = "timeSeries"
          stacked = false
          region  = local.region
          period  = local.dashboard_period
          stat    = "Sum"
          metrics = concat(
            [for a in var.waf_regional_web_acl_names : ["AWS/WAFV2", "BlockedRequests", "WebACL", a, "Rule", "ALL", "Region", local.region]],
            [for a in var.cloudfront_waf_web_acl_names : ["AWS/WAFV2", "BlockedRequests", "WebACL", a, "Rule", "ALL", "Region", local.cloudfront_waf_dimension_region, { region = local.cloudfront_waf_region }]],
          )
        }
      }
    },
    {
      enabled = length(var.dynamodb_table_names) > 0
      widget = {
        type = "metric"
        properties = {
          title   = "DynamoDB consumed capacity"
          view    = "timeSeries"
          stacked = false
          region  = local.region
          period  = local.dashboard_period
          stat    = "Sum"
          metrics = concat(
            [for t in var.dynamodb_table_names : ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", t]],
            [for t in var.dynamodb_table_names : ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", t]],
          )
        }
      }
    },
    {
      enabled = length(var.dynamodb_table_names) > 0
      widget = {
        type = "metric"
        properties = {
          title   = "DynamoDB throttle events"
          view    = "timeSeries"
          stacked = false
          region  = local.region
          period  = local.dashboard_period
          stat    = "Sum"
          metrics = concat(
            [for t in var.dynamodb_table_names : ["AWS/DynamoDB", "ReadThrottleEvents", "TableName", t]],
            [for t in var.dynamodb_table_names : ["AWS/DynamoDB", "WriteThrottleEvents", "TableName", t]],
          )
        }
      }
    },
    {
      enabled = length(var.log_metric_filters) > 0
      widget = {
        type = "metric"
        properties = {
          title   = "Log metric filters"
          view    = "timeSeries"
          stacked = false
          region  = local.region
          period  = local.dashboard_period
          stat    = "Sum"
          metrics = [for k in keys(var.log_metric_filters) : [local.metric_namespace, k]]
        }
      }
    },
  ]

  enabled_widgets = [for c in local.widget_candidates : c.widget if c.enabled]

  # Two widgets per row, 12 columns wide and 6 rows high.
  dashboard_widgets = [
    for i, w in local.enabled_widgets : merge(w, {
      x      = (i % 2) * 12
      y      = floor(i / 2) * 6
      width  = 12
      height = 6
    })
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = local.dashboard_name
  dashboard_body = jsonencode({ widgets = local.dashboard_widgets })
}

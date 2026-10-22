data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region

  dashboard_name = "${var.name_prefix}-overview"

  # Namespace of the custom metrics produced by the log metric filters.
  metric_namespace = "${var.name_prefix}/Logs"

  # CloudFront-scope web ACL metrics are only published in us-east-1, with the "Global" region dimension.
  cloudfront_waf_region           = "us-east-1"
  cloudfront_waf_dimension_region = "Global"

  alarm_actions = [var.alarm_topic_arn]

  # Authentication failure filter, merged with the caller's filters so that both share one resource and one alarm block.
  auth_filter = var.auth_failure_log_group_name == null ? {} : {
    "auth-failures" = {
      log_group_name  = var.auth_failure_log_group_name
      pattern         = var.auth_failure_filter_pattern
      alarm_threshold = var.auth_failure_threshold
    }
  }

  metric_filters = merge(var.log_metric_filters, local.auth_filter)

  # Only the filters with a threshold get an alarm.
  alarmed_metric_filters = { for k, f in local.metric_filters : k => f if f.alarm_threshold != null }
}

# Metric filters only attach to log groups owned by the producers (lambda-service, API stage, WAF logging).
# No log group is created, subscribed or exported here.
#
# Each filter counts matching events (value 1). No field is extracted and no dimension is set, so nothing from the
# log content (identifiers, tokens, PII) reaches CloudWatch metrics.
resource "aws_cloudwatch_log_metric_filter" "this" {
  for_each = local.metric_filters

  name           = "${var.name_prefix}-${each.key}"
  log_group_name = each.value.log_group_name
  pattern        = each.value.pattern

  metric_transformation {
    name      = each.key
    namespace = local.metric_namespace
    value     = "1"
    unit      = "Count"
  }
}

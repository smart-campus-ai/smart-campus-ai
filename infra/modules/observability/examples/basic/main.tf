# Basic example: observability module with all resources observed.
#
# This example is not runnable standalone: it requires the SNS topic ARN
# and a us-east-1 provider alias for CloudFront WAF alarms.
# See the platform stack for a complete instantiation.

module "observability" {
  source = "../.."

  name_prefix     = "sc-dev"
  alarm_topic_arn = "arn:aws:sns:us-east-1:123456789012:sc-dev-ops"

  api = {
    name       = "sc-dev-api"
    stage_name = "live"
  }

  lambda_function_names        = ["sc-dev-tickets", "sc-dev-chat"]
  dynamodb_table_names         = ["sc-dev-tickets"]
  dlq_queue_names              = ["sc-dev-tickets-dlq"]
  waf_regional_web_acl_names   = ["sc-dev-api"]
  cloudfront_waf_web_acl_names = ["sc-dev-edge"]

  auth_failure_log_group_name = "/aws/apigateway/sc-dev-api-access"

  tags = {
    Environment = "dev"
  }
}

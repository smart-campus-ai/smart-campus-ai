# Two web ACLs (RF04, ADR-0004): CLOUDFRONT scope on the distribution and REGIONAL scope on the API stage, so that the
# rate limits apply whichever URL (CloudFront or execute-api) is used. Both log to a KMS-encrypted CloudWatch log group
# with the foundation "logs" key.
#
# The REGIONAL ACL is associated here, from the stage ARN of the rest-api module. The web_acl_arn input of rest-api is
# left null on purpose: setting both would create the same association twice.

# The CLOUDFRONT web ACL only exists in us-east-1, hence the aliased provider. Its log group lives in that region too,
# so the "logs" key must be a us-east-1 key (always true while aws_region is us-east-1, ADR-0013).
module "waf_cloudfront" {
  count  = var.enable_waf ? 1 : 0
  source = "../../modules/waf"

  providers = { aws = aws.us_east_1 }

  name_prefix        = var.name_prefix
  scope              = "CLOUDFRONT"
  kms_key_arn        = local.kms_key_arns["logs"]
  log_retention_days = var.log_retention_in_days

  rate_limit_per_ip         = var.waf_rate_limit_per_ip
  rate_limit_window_seconds = var.waf_rate_limit_window_seconds
}

# The per-user rule (Authorization header) lives on the REGIONAL ACL only: it sees the token whichever URL is used.
module "waf_regional" {
  count  = var.enable_waf ? 1 : 0
  source = "../../modules/waf"

  name_prefix        = var.name_prefix
  scope              = "REGIONAL"
  kms_key_arn        = local.kms_key_arns["logs"]
  log_retention_days = var.log_retention_in_days

  rate_limit_per_ip            = var.waf_rate_limit_per_ip
  rate_limit_per_authorization = var.waf_rate_limit_per_authorization
  rate_limit_window_seconds    = var.waf_rate_limit_window_seconds

  associated_resource_arns = { api = module.rest_api.stage_arn }
}

check "waf_cloudfront_logs_key_region" {
  assert {
    condition     = !var.enable_waf || strcontains(local.kms_key_arns["logs"], ":kms:us-east-1:")
    error_message = "The log group of the CLOUDFRONT web ACL is created in us-east-1, so the foundation \"logs\" key must be a us-east-1 key. With another aws_region, give the CLOUDFRONT ACL its own us-east-1 logs key."
  }
}

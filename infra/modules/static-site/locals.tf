data "aws_caller_identity" "current" {}

locals {
  name = "${var.name_prefix}-spa"

  # S3 bucket names are global: the account ID keeps the name unique without any hardcoded value.
  bucket_name = "${local.name}-${data.aws_caller_identity.current.account_id}"

  s3_origin_id  = "spa-s3"
  api_origin_id = "api-gateway"

  # Zero or one API origin, keyed by a stable string so that dependent blocks and resources can be conditional.
  api_origins = var.api_origin_domain_name == null ? {} : { api = var.api_origin_domain_name }

  # Global AWS managed cache policies (constants, identical in every account and partition).
  cache_policy_caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  cache_policy_caching_disabled  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

  # S3 answers 403 (no ListBucket permission) or 404 for client-side routes: serve the SPA entry point instead.
  spa_error_codes = toset([403, 404])

  hsts_max_age_seconds = 63072000

  logging_enabled       = var.logging_bucket_name != null
  s3_access_log_prefix  = "s3/${local.bucket_name}/"
  cloudfront_log_prefix = "cloudfront/${local.name}/"
}

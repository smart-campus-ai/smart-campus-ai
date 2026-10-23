locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  foundation_ssm_prefix = "/smartcampus/${var.env}/foundation"
  platform_ssm_prefix   = "/smartcampus/${var.env}/platform"

  # KMS key ARNs by domain (data, logs, ai), read from the foundation contract (main.tf).
  kms_key_arns = { for domain, parameter in data.aws_ssm_parameter.kms : domain => parameter.insecure_value }

  # The Cognito hosted domain is built from its prefix instead of read from the identity module: the CSP of the site
  # needs it, and the identity module needs the site URL for its callback URLs.
  cognito_domain_prefix    = coalesce(var.cognito_domain_prefix, "${var.name_prefix}-auth")
  cognito_hosted_ui_origin = "https://${local.cognito_domain_prefix}.auth.${local.region}.amazoncognito.com"

  # Cognito callback and logout URLs: the CloudFront URL of the site (no custom domain, ADR-0003) and, in dev, the
  # local development origins.
  spa_callback_urls = concat(
    ["${module.static_site.site_url}${var.spa_callback_path}"],
    [for origin in var.local_origins : "${origin}${var.spa_callback_path}"],
  )

  attachments_origin = "https://${module.attachments_bucket.bucket_regional_domain_name}"

  # Content Security Policy of the SPA, a single line that contains frame-ancestors 'none'. Aligned with SE: the SPA
  # talks to its own origin (/api/*), to the Cognito hosted domain and endpoint, and to the attachments bucket
  # (presigned POST and GET).
  content_security_policy = join("; ", [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self'",
    "img-src 'self' data: ${local.attachments_origin}",
    "font-src 'self'",
    "connect-src 'self' ${local.cognito_hosted_ui_origin} https://cognito-idp.${local.region}.${data.aws_partition.current.dns_suffix} ${local.attachments_origin}",
    "form-action 'self' ${local.attachments_origin}",
    "base-uri 'self'",
    "object-src 'none'",
    "frame-ancestors 'none'",
  ])

  # Routes served by each function through API Gateway. Keep in sync with openapi/openapi.json.tftpl (the
  # api_routes_match_openapi check in api.tf compares both after apply).
  api_routes = {
    tickets = ["GET /tickets", "POST /tickets", "GET /tickets/{ticketId}", "PATCH /tickets/{ticketId}"]
    kpi     = ["GET /kpi"]
    chat    = ["POST /chat"]
  }

  # kb-sync cannot receive the knowledge base identifiers as plain environment variables: the knowledge base needs the
  # kb-sync alias ARN (S3 notification), so kb-sync must not depend on the knowledge base. It reads these parameters,
  # published in ssm.tf, at runtime.
  kb_sync_parameter_names = {
    knowledge_base_id = "${local.platform_ssm_prefix}/kb/knowledge_base_id"
    data_source_id    = "${local.platform_ssm_prefix}/kb/data_source_id"
  }

  lambda_function_names = {
    tickets          = module.tickets.function_name
    kpi              = module.kpi.function_name
    chat             = module.chat.function_name
    escalation       = module.escalation.function_name
    notifier         = module.notifier.function_name
    "kb-sync"        = module.kb_sync.function_name
    "kpi-aggregator" = module.kpi_aggregator.function_name
    "pre-token"      = module.pre_token.function_name
  }
}

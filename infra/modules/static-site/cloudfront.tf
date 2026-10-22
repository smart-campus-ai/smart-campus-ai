resource "aws_cloudfront_origin_access_control" "site" {
  name                              = local.name
  description                       = "OAC of the ${local.name} SPA bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_response_headers_policy" "security" {
  name    = "${local.name}-security-headers"
  comment = "Security headers of the ${local.name} distribution"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = local.hsts_max_age_seconds
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    content_security_policy {
      content_security_policy = var.content_security_policy
      override                = true
    }
  }
}

# Forwards the Cognito access token to API Gateway, which validates it with its native authorizer.
# Host is deliberately not forwarded: API Gateway expects its own host name.
resource "aws_cloudfront_origin_request_policy" "api" {
  for_each = local.api_origins

  name    = "${local.name}-api"
  comment = "Forwards Authorization and the query string to the API origin"

  cookies_config {
    cookie_behavior = "none"
  }

  headers_config {
    header_behavior = "whitelist"

    headers {
      items = ["Authorization"]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

# The distribution serves the SPA publicly by design, behind the optional WAF (web_acl_id, RF04), so the
# following findings are accepted with the reason below.
# AVD-AWS-0010: standard logging is optional (logging_bucket_name); no log bucket exists yet and CloudFront
# standard logging needs an ACL-enabled bucket, which the observability brick provides and the stack wires in.
#trivy:ignore:AVD-AWS-0010
#trivy:ignore:AVD-AWS-0011
#trivy:ignore:AVD-AWS-0013
resource "aws_cloudfront_distribution" "site" {
  # checkov:skip=CKV_AWS_68: The CLOUDFRONT-scope web ACL is created by the WAF brick (RF04) and attached through web_acl_id.
  # checkov:skip=CKV2_AWS_47: Log4j protection comes from the AWSManagedRulesKnownBadInputsRuleSet of the web ACL attached through web_acl_id (RF04).
  # checkov:skip=CKV_AWS_86: Standard logging is optional (logging_bucket_name); the log bucket belongs to the observability brick and is wired by the stack.
  # checkov:skip=CKV_AWS_310: A single S3 origin has nothing to fail over to; the API origin is a different service.
  # checkov:skip=CKV_AWS_374: No geo restriction: the campus audience is not tied to a country (students abroad).
  # checkov:skip=CKV_AWS_174: Without a custom domain (ADR-0003) the default *.cloudfront.net certificate is used and CloudFront ignores the minimum protocol version; with acm_certificate_arn it is TLSv1.2_2021.
  # checkov:skip=CKV2_AWS_42: No custom domain is available (ADR-0003); the default certificate is used until acm_certificate_arn is provided.
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.name} SPA"
  default_root_object = "index.html"
  price_class         = var.price_class
  http_version        = "http2and3"
  web_acl_id          = var.web_acl_id
  aliases             = var.aliases

  origin {
    origin_id                = local.s3_origin_id
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  dynamic "origin" {
    for_each = local.api_origins

    content {
      origin_id   = local.api_origin_id
      domain_name = origin.value
      origin_path = var.api_origin_path

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  default_cache_behavior {
    target_origin_id           = local.s3_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.cache_policy_caching_optimized
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }

  dynamic "ordered_cache_behavior" {
    for_each = local.api_origins

    content {
      path_pattern               = "/api/*"
      target_origin_id           = local.api_origin_id
      viewer_protocol_policy     = "redirect-to-https"
      allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods             = ["GET", "HEAD"]
      compress                   = true
      cache_policy_id            = local.cache_policy_caching_disabled
      origin_request_policy_id   = aws_cloudfront_origin_request_policy.api[ordered_cache_behavior.key].id
      response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
    }
  }

  dynamic "custom_error_response" {
    for_each = local.spa_error_codes

    content {
      error_code            = custom_error_response.value
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == null ? true : null
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn == null ? null : "sni-only"
    minimum_protocol_version       = var.acm_certificate_arn == null ? null : "TLSv1.2_2021"
  }

  dynamic "logging_config" {
    for_each = local.logging_enabled ? { logging = var.logging_bucket_name } : {}

    content {
      bucket          = "${logging_config.value}.s3.amazonaws.com"
      prefix          = local.cloudfront_log_prefix
      include_cookies = false
    }
  }

  tags = merge(var.tags, { Name = local.name })
}

mock_provider "aws" {
  # Fake documentation account ID, used only to keep names and conditions predictable.
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  # Computed attributes are unknown at plan time; the bucket policy and the distribution consume them.
  override_resource {
    target = aws_s3_bucket.site
    values = {
      id                          = "sc-dev-spa-123456789012"
      arn                         = "arn:aws:s3:::sc-dev-spa-123456789012"
      bucket_regional_domain_name = "sc-dev-spa-123456789012.s3.eu-west-3.amazonaws.com"
    }
  }

  override_resource {
    target = aws_cloudfront_distribution.site
    values = {
      id          = "E1ABCDEFGHIJKL"
      arn         = "arn:aws:cloudfront::123456789012:distribution/E1ABCDEFGHIJKL"
      domain_name = "d1234567890abc.cloudfront.net"
    }
  }

  override_resource {
    target = aws_cloudfront_origin_access_control.site
    values = {
      id = "E2OACOACOACOAC"
    }
  }

  override_resource {
    target = aws_cloudfront_response_headers_policy.security
    values = {
      id = "11111111-1111-1111-1111-111111111111"
    }
  }

  override_resource {
    target = aws_cloudfront_origin_request_policy.api
    values = {
      id = "22222222-2222-2222-2222-222222222222"
    }
  }

  # The mock returns random strings for computed attributes, which aws_s3_bucket_policy.policy rejects as invalid
  # JSON. The invariants are asserted on the document arguments (known at plan), not on the JSON.
  override_data {
    target = data.aws_iam_policy_document.bucket
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix             = "sc-dev"
  kms_key_arn             = "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000"
  content_security_policy = "default-src 'self'; connect-src 'self' https://cognito-idp.eu-west-3.amazonaws.com; frame-ancestors 'none'"
}

# EN21-AC1: bucket blocks all public access and enforces bucket owner
run "en21_ac1_bucket_public_access_blocked" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.site.block_public_acls,
      aws_s3_bucket_public_access_block.site.block_public_policy,
      aws_s3_bucket_public_access_block.site.ignore_public_acls,
      aws_s3_bucket_public_access_block.site.restrict_public_buckets,
    ])
    error_message = "Block Public Access must be fully enabled on the SPA bucket."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.site.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "Object ownership must be BucketOwnerEnforced."
  }

  assert {
    condition     = aws_s3_bucket.site.bucket == "sc-dev-spa-123456789012" && aws_s3_bucket.site.force_destroy == false
    error_message = "Bucket name must be <prefix>-spa-<account id> and the bucket must never be force-destroyed."
  }
}

# EN21-AC1: versioning is enabled and the default encryption is SSE-KMS with the input key and bucket key
run "en21_ac1_bucket_versioned_and_encrypted_with_cmk" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_versioning.site.versioning_configuration).status == "Enabled"
    error_message = "Versioning must be enabled on the SPA bucket."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.site.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "Default encryption must be aws:kms."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.site.rule).apply_server_side_encryption_by_default).kms_master_key_id == var.kms_key_arn
    error_message = "Default encryption must use the kms_key_arn input."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.site.rule).bucket_key_enabled == true
    error_message = "S3 Bucket Keys must be enabled."
  }
}

# EN21-AC1: the bucket policy grants read only to CloudFront, scoped to the distribution
run "en21_ac1_bucket_policy_allows_only_the_distribution" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket.statement :
      s.sid == "AllowCloudFrontRead" && s.effect == "Allow" &&
      toset(s.actions) == toset(["s3:GetObject"]) &&
      toset(s.resources) == toset(["arn:aws:s3:::sc-dev-spa-123456789012/*"]) &&
      alltrue([for p in s.principals : p.type == "Service" && toset(p.identifiers) == toset(["cloudfront.amazonaws.com"])]) &&
      anytrue([
        for c in s.condition :
        c.test == "StringEquals" && c.variable == "aws:SourceArn" && toset(c.values) == toset(["arn:aws:cloudfront::123456789012:distribution/E1ABCDEFGHIJKL"])
      ])
    ])
    error_message = "AllowCloudFrontRead must grant s3:GetObject to cloudfront.amazonaws.com with aws:SourceArn set to the distribution ARN."
  }

  assert {
    condition     = length([for s in data.aws_iam_policy_document.bucket.statement : s if s.effect == "Allow"]) == 1
    error_message = "The CloudFront statement must be the only Allow statement of the bucket policy."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.bucket.statement :
      alltrue([for p in s.principals : !contains(p.identifiers, "*")]) if s.effect == "Allow"
    ])
    error_message = "No Allow statement may use a \"*\" principal."
  }
}

# EN21-AC1: the bucket policy denies insecure transport and outdated TLS
run "en21_ac1_bucket_policy_denies_insecure_transport" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket.statement :
      s.sid == "DenyInsecureTransport" && s.effect == "Deny" && contains(s.actions, "s3:*") &&
      contains(s.resources, "arn:aws:s3:::sc-dev-spa-123456789012") && contains(s.resources, "arn:aws:s3:::sc-dev-spa-123456789012/*") &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SecureTransport" && c.test == "Bool" && contains(c.values, "false")
      ])
    ])
    error_message = "The bucket policy must deny requests without aws:SecureTransport."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.bucket.statement :
      s.sid == "DenyOutdatedTls" && s.effect == "Deny" && anytrue([
        for c in s.condition :
        c.variable == "s3:TlsVersion" && c.test == "NumericLessThan" && contains(c.values, "1.2")
      ])
    ])
    error_message = "The bucket policy must deny TLS versions below 1.2."
  }
}

# EN21-AC1: lifecycle expires noncurrent versions and aborts incomplete uploads
run "en21_ac1_lifecycle_rules" {
  command = plan

  variables {
    noncurrent_version_expiration_days     = 14
    abort_incomplete_multipart_upload_days = 3
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.site.rule : r if r.id == "expire-noncurrent-versions"
    ]).noncurrent_version_expiration).noncurrent_days == 14
    error_message = "Noncurrent versions must expire after noncurrent_version_expiration_days."
  }

  assert {
    condition = one(one([
      for r in aws_s3_bucket_lifecycle_configuration.site.rule : r if r.id == "abort-incomplete-multipart-uploads"
    ]).abort_incomplete_multipart_upload).days_after_initiation == 3
    error_message = "Incomplete multipart uploads must be aborted after the configured days."
  }

  assert {
    condition     = alltrue([for r in aws_s3_bucket_lifecycle_configuration.site.rule : r.status == "Enabled"])
    error_message = "Every lifecycle rule must be enabled."
  }
}

# EN21-AC1: logging is off by default
run "en21_ac1_logging_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_logging.site) == 0
    error_message = "S3 access logging must be disabled unless a logging bucket is given."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.site.logging_config) == 0
    error_message = "CloudFront standard logging must be disabled unless a logging bucket is given."
  }
}

# EN21-AC1: logging targets the given bucket when set
run "en21_ac1_logging_targets_given_bucket" {
  command = plan

  variables {
    logging_bucket_name = "sc-dev-logs"
  }

  assert {
    condition     = one(aws_s3_bucket_logging.site).target_bucket == "sc-dev-logs"
    error_message = "S3 access logs must be delivered to logging_bucket_name."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.site.logging_config).bucket == "sc-dev-logs.s3.amazonaws.com"
    error_message = "CloudFront logs must be delivered to the logging bucket."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.site.logging_config).include_cookies == false
    error_message = "CloudFront logs must not include cookies."
  }
}

# EN21-AC2: viewers are redirected from HTTP to HTTPS on every behaviour
run "en21_ac2_https_redirect" {
  command = plan

  variables {
    api_origin_domain_name = "abc123.execute-api.eu-west-3.amazonaws.com"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.site.default_cache_behavior).viewer_protocol_policy == "redirect-to-https"
    error_message = "The default behaviour must redirect HTTP to HTTPS."
  }

  assert {
    condition     = alltrue([for b in aws_cloudfront_distribution.site.ordered_cache_behavior : b.viewer_protocol_policy == "redirect-to-https"])
    error_message = "Every ordered behaviour must redirect HTTP to HTTPS."
  }
}

# EN21-AC2: default CloudFront certificate without a custom domain
run "en21_ac2_default_certificate_without_domain" {
  command = plan

  assert {
    condition     = one(aws_cloudfront_distribution.site.viewer_certificate).cloudfront_default_certificate == true
    error_message = "Without a custom domain the default CloudFront certificate must be used."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.site.aliases) == 0
    error_message = "No alias is expected without a custom domain."
  }
}

# EN21-AC2: TLSv1.2_2021 minimum with a custom certificate
run "en21_ac2_tls_minimum_with_custom_certificate" {
  command = plan

  variables {
    aliases             = ["app.example.org"]
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.site.viewer_certificate).minimum_protocol_version == "TLSv1.2_2021"
    error_message = "The minimum protocol version must be TLSv1.2_2021."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.site.viewer_certificate).ssl_support_method == "sni-only"
    error_message = "The certificate must be served with SNI only."
  }
}

# EN21-AC2: the origin is reached through OAC with sigv4 and no legacy OAI
run "en21_ac2_origin_access_control_sigv4" {
  command = plan

  assert {
    condition = (
      aws_cloudfront_origin_access_control.site.origin_access_control_origin_type == "s3" &&
      aws_cloudfront_origin_access_control.site.signing_behavior == "always" &&
      aws_cloudfront_origin_access_control.site.signing_protocol == "sigv4"
    )
    error_message = "The OAC must sign S3 requests with sigv4, always."
  }

  assert {
    condition = anytrue([
      for o in aws_cloudfront_distribution.site.origin :
      o.origin_id == "spa-s3" && o.origin_access_control_id == "E2OACOACOACOAC"
    ])
    error_message = "The S3 origin must use the OAC."
  }

  assert {
    condition     = alltrue([for o in aws_cloudfront_distribution.site.origin : length(o.s3_origin_config) == 0])
    error_message = "The legacy origin access identity must not be used."
  }
}

# EN21-AC2: the SPA error mapping serves index.html for 403 and 404
run "en21_ac2_spa_error_mapping" {
  command = plan

  assert {
    condition     = toset([for e in aws_cloudfront_distribution.site.custom_error_response : e.error_code]) == toset([403, 404])
    error_message = "403 and 404 must be mapped."
  }

  assert {
    condition = alltrue([
      for e in aws_cloudfront_distribution.site.custom_error_response :
      e.response_page_path == "/index.html" && e.response_code == 200
    ])
    error_message = "Mapped errors must return /index.html with a 200 status."
  }

  assert {
    condition     = aws_cloudfront_distribution.site.default_root_object == "index.html"
    error_message = "The default root object must be index.html."
  }
}

# EN21-AC2: price class and WAF are inputs
run "en21_ac2_price_class_and_web_acl_inputs" {
  command = plan

  variables {
    price_class = "PriceClass_200"
    web_acl_id  = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/sc-dev-edge/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = aws_cloudfront_distribution.site.price_class == "PriceClass_200"
    error_message = "The price class must follow the variable."
  }

  assert {
    condition     = aws_cloudfront_distribution.site.web_acl_id == var.web_acl_id
    error_message = "The web ACL must be attached when web_acl_id is set."
  }
}

# EN21-AC2: no WAF and the cheapest price class by default
run "en21_ac2_defaults_without_web_acl" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.site.web_acl_id == null
    error_message = "No web ACL must be attached by default."
  }

  assert {
    condition     = aws_cloudfront_distribution.site.price_class == "PriceClass_100"
    error_message = "The default price class must be PriceClass_100."
  }
}

# EN21-AC3: security headers
run "en21_ac3_security_headers" {
  command = plan

  assert {
    condition     = one(aws_cloudfront_distribution.site.default_cache_behavior).response_headers_policy_id == "11111111-1111-1111-1111-111111111111"
    error_message = "The default behaviour must attach the security headers policy."
  }

  assert {
    condition = (
      one(one(aws_cloudfront_response_headers_policy.security.security_headers_config).strict_transport_security).access_control_max_age_sec >= 31536000 &&
      one(one(aws_cloudfront_response_headers_policy.security.security_headers_config).strict_transport_security).include_subdomains == true &&
      one(one(aws_cloudfront_response_headers_policy.security.security_headers_config).strict_transport_security).preload == true &&
      one(one(aws_cloudfront_response_headers_policy.security.security_headers_config).strict_transport_security).override == true
    )
    error_message = "HSTS must be set for at least one year, with includeSubDomains, preload and override (CKV_AWS_259)."
  }

  assert {
    condition     = one(one(aws_cloudfront_response_headers_policy.security.security_headers_config).content_type_options).override == true
    error_message = "X-Content-Type-Options: nosniff must be set."
  }

  assert {
    condition     = one(one(aws_cloudfront_response_headers_policy.security.security_headers_config).frame_options).frame_option == "DENY"
    error_message = "X-Frame-Options must be DENY."
  }

  assert {
    condition     = one(one(aws_cloudfront_response_headers_policy.security.security_headers_config).referrer_policy).referrer_policy == "strict-origin-when-cross-origin"
    error_message = "Referrer-Policy must be set."
  }

  assert {
    condition     = one(one(aws_cloudfront_response_headers_policy.security.security_headers_config).content_security_policy).content_security_policy == var.content_security_policy
    error_message = "The CSP must come from the content_security_policy variable."
  }

  assert {
    condition     = can(regex("frame-ancestors 'none'", one(one(aws_cloudfront_response_headers_policy.security.security_headers_config).content_security_policy).content_security_policy))
    error_message = "The CSP must contain frame-ancestors 'none'."
  }
}

# EN21-AC3: rejects a CSP without frame-ancestors 'none'
run "en21_ac3_rejects_csp_without_frame_ancestors" {
  command = plan

  variables {
    content_security_policy = "default-src 'self'"
  }

  expect_failures = [var.content_security_policy]
}

# EN21-AC3: rejects a multi-line CSP
run "en21_ac3_rejects_multiline_csp" {
  command = plan

  variables {
    content_security_policy = "default-src 'self';\nframe-ancestors 'none'"
  }

  expect_failures = [var.content_security_policy]
}

# EN21-AC4: no API behaviour until an API origin is given
run "en21_ac4_no_api_behaviour_without_origin" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_distribution.site.ordered_cache_behavior) == 0
    error_message = "No ordered behaviour is expected without api_origin_domain_name."
  }

  assert {
    condition     = length(aws_cloudfront_origin_request_policy.api) == 0
    error_message = "No origin request policy is expected without api_origin_domain_name."
  }
}

# EN21-AC4: /api/* targets the API origin with caching disabled
run "en21_ac4_api_behaviour_cache_disabled" {
  command = plan

  variables {
    api_origin_domain_name = "abc123.execute-api.eu-west-3.amazonaws.com"
    api_origin_path        = "/live"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.site.ordered_cache_behavior) == 1
    error_message = "Exactly one ordered behaviour (/api/*) is expected."
  }

  assert {
    condition = anytrue([
      for b in aws_cloudfront_distribution.site.ordered_cache_behavior :
      b.path_pattern == "/api/*" && b.target_origin_id == "api-gateway" &&
      b.cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" &&
      toset(b.cached_methods) == toset(["GET", "HEAD"])
    ])
    error_message = "/api/* must target the API origin with the CachingDisabled policy."
  }

  assert {
    condition = anytrue([
      for o in aws_cloudfront_distribution.site.origin :
      o.origin_id == "api-gateway" && o.domain_name == "abc123.execute-api.eu-west-3.amazonaws.com" && o.origin_path == "/live" &&
      alltrue([for c in o.custom_origin_config : c.origin_protocol_policy == "https-only" && toset(c.origin_ssl_protocols) == toset(["TLSv1.2"])])
    ])
    error_message = "The API origin must be reached over HTTPS only with TLSv1.2, on the configured stage path."
  }

  assert {
    condition     = length([for o in aws_cloudfront_distribution.site.origin : o if o.origin_id == "api-gateway" && o.origin_access_control_id != null && o.origin_access_control_id != ""]) == 0
    error_message = "The API origin must not use the S3 OAC."
  }
}

# EN21-AC4: the Authorization header is forwarded by an origin request policy
run "en21_ac4_authorization_header_forwarded" {
  command = plan

  variables {
    api_origin_domain_name = "abc123.execute-api.eu-west-3.amazonaws.com"
  }

  assert {
    condition = anytrue([
      for b in aws_cloudfront_distribution.site.ordered_cache_behavior :
      b.origin_request_policy_id == "22222222-2222-2222-2222-222222222222"
    ])
    error_message = "/api/* must use the API origin request policy."
  }

  assert {
    condition     = one(aws_cloudfront_origin_request_policy.api["api"].headers_config).header_behavior == "whitelist"
    error_message = "Only whitelisted headers must be forwarded."
  }

  assert {
    condition     = contains(flatten([for h in one(aws_cloudfront_origin_request_policy.api["api"].headers_config).headers : h.items]), "Authorization")
    error_message = "The Authorization header must be forwarded to the API origin."
  }

  assert {
    condition     = one(aws_cloudfront_origin_request_policy.api["api"].cookies_config).cookie_behavior == "none"
    error_message = "Cookies must not be forwarded to the API origin."
  }
}

# EN21-AC5: direct access to the bucket is refused (no public path, no principal other than the distribution)
run "en21_ac5_direct_bucket_access_refused" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.site.block_public_acls,
      aws_s3_bucket_public_access_block.site.block_public_policy,
      aws_s3_bucket_public_access_block.site.ignore_public_acls,
      aws_s3_bucket_public_access_block.site.restrict_public_buckets,
    ])
    error_message = "Block Public Access must be fully enabled."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.bucket.statement :
      alltrue([for p in s.principals : p.type == "Service" && p.identifiers == toset(["cloudfront.amazonaws.com"])]) if s.effect == "Allow"
    ])
    error_message = "Only the CloudFront service principal may be allowed on the bucket."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.site.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled (BucketOwnerEnforced)."
  }
}

# EN21-AC1: rejects an invalid name_prefix
run "en21_ac1_rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Bad_Prefix"
  }

  expect_failures = [var.name_prefix]
}

# EN21-AC1: rejects a KMS alias instead of a key ARN
run "en21_ac1_rejects_kms_alias" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-3:123456789012:alias/sc-dev-data"
  }

  expect_failures = [var.kms_key_arn]
}

# EN21-AC1: rejects an invalid logging bucket name
run "en21_ac1_rejects_invalid_logging_bucket_name" {
  command = plan

  variables {
    logging_bucket_name = "Not_A_Bucket"
  }

  expect_failures = [var.logging_bucket_name]
}

# EN21-AC2: rejects an unknown price class
run "en21_ac2_rejects_invalid_price_class" {
  command = plan

  variables {
    price_class = "PriceClass_50"
  }

  expect_failures = [var.price_class]
}

# EN21-AC2: rejects a web ACL that is not CLOUDFRONT scope
run "en21_ac2_rejects_regional_web_acl" {
  command = plan

  variables {
    web_acl_id = "arn:aws:wafv2:eu-west-3:123456789012:regional/webacl/sc-dev-api/00000000-0000-0000-0000-000000000000"
  }

  expect_failures = [var.web_acl_id]
}

# EN21-AC2: rejects aliases without a certificate
run "en21_ac2_rejects_aliases_without_certificate" {
  command = plan

  variables {
    aliases = ["app.example.org"]
  }

  expect_failures = [var.aliases]
}

# EN21-AC2: rejects a certificate outside us-east-1
run "en21_ac2_rejects_certificate_outside_us_east_1" {
  command = plan

  variables {
    aliases             = ["app.example.org"]
    acm_certificate_arn = "arn:aws:acm:eu-west-3:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  }

  expect_failures = [var.acm_certificate_arn]
}

# EN21-AC4: rejects an API origin given as a URL
run "en21_ac4_rejects_api_origin_url" {
  command = plan

  variables {
    api_origin_domain_name = "https://abc123.execute-api.eu-west-3.amazonaws.com/live"
  }

  expect_failures = [var.api_origin_domain_name]
}

# EN21-AC4: rejects an API origin path with a trailing slash
run "en21_ac4_rejects_api_origin_path_with_trailing_slash" {
  command = plan

  variables {
    api_origin_path = "/live/"
  }

  expect_failures = [var.api_origin_path]
}

# EN21-AC1: rejects lifecycle durations below 1
run "en21_ac1_rejects_noncurrent_days_below_1" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 0
  }

  expect_failures = [var.noncurrent_version_expiration_days]
}

run "en21_ac1_rejects_multipart_days_below_1" {
  command = plan

  variables {
    abort_incomplete_multipart_upload_days = 0
  }

  expect_failures = [var.abort_incomplete_multipart_upload_days]
}

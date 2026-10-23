resource "aws_wafv2_ip_set" "this" {
  for_each = local.ip_sets

  name               = "${local.name}-${each.key}"
  description        = "${each.value.action == "label" ? "Allowed" : "Blocked"} ${each.value.version} addresses of ${local.name}."
  scope              = var.scope
  ip_address_version = each.value.version
  addresses          = each.value.addresses

  tags = merge(var.tags, { Name = "${local.name}-${each.key}" })
}

resource "aws_wafv2_web_acl" "this" {
  name        = local.name
  description = "${var.scope} web ACL of ${var.name_prefix}: AWS managed rule groups, body size limit and rate limiting."
  scope       = var.scope

  default_action {
    allow {}
  }

  custom_response_body {
    key          = local.rate_limited_body_key
    content_type = "APPLICATION_JSON"
    content      = jsonencode({ message = "Too many requests" })
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.name
    sampled_requests_enabled   = var.enable_sampled_requests
  }

  # Explicit IP deny and allow lists. A denied address is blocked. An allowed address is only counted and labelled:
  # the label makes the rate-based rules skip it, while the body size limit and the managed groups (SQLi, Log4j...)
  # still inspect it.
  dynamic "rule" {
    for_each = local.ip_sets

    content {
      name     = "ip-${rule.key}"
      priority = rule.value.priority

      action {
        dynamic "count" {
          for_each = rule.value.action == "label" ? [1] : []
          content {}
        }

        dynamic "block" {
          for_each = rule.value.action == "block" ? [1] : []
          content {}
        }
      }

      dynamic "rule_label" {
        for_each = rule.value.action == "label" ? [1] : []

        content {
          name = local.allowed_ip_label_name
        }
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.this[rule.key].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.name}-ip-${rule.key}"
        sampled_requests_enabled   = var.enable_sampled_requests
      }
    }
  }

  # A body above the limit is blocked (403); a body above the inspection size counts as matching.
  rule {
    name     = "body-size-limit"
    priority = local.priorities.body_size

    action {
      block {}
    }

    statement {
      size_constraint_statement {
        comparison_operator = "GT"
        size                = var.max_body_size_bytes

        field_to_match {
          body {
            oversize_handling = "MATCH"
          }
        }

        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-body-size-limit"
      sampled_requests_enabled   = var.enable_sampled_requests
    }
  }

  # Rate-based rules: per IP, and per Authorization header (per user) when rate_limit_per_authorization is set.
  # Offenders get a 429 with a Retry-After header until their rate falls back under the limit.
  dynamic "rule" {
    for_each = local.rate_rules

    content {
      name     = rule.key
      priority = rule.value.priority

      action {
        block {
          custom_response {
            response_code            = 429
            custom_response_body_key = local.rate_limited_body_key

            response_header {
              name  = "Retry-After"
              value = tostring(var.rate_limit_window_seconds)
            }
          }
        }
      }

      statement {
        rate_based_statement {
          limit                 = rule.value.limit
          evaluation_window_sec = var.rate_limit_window_seconds
          aggregate_key_type    = rule.value.by_authorization ? "CUSTOM_KEYS" : "IP"

          dynamic "custom_key" {
            for_each = rule.value.by_authorization ? [1] : []

            content {
              header {
                name = "authorization"

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }

          # Narrowing conditions: the path prefix (per-user rule only, the per-IP rule covers every URL) and "not
          # from an allowed IP". Two conditions need an and_statement.
          dynamic "scope_down_statement" {
            for_each = rule.value.use_path_prefix || rule.value.skip_allowed_ips ? [1] : []

            content {
              dynamic "byte_match_statement" {
                for_each = rule.value.use_path_prefix && !rule.value.skip_allowed_ips ? [1] : []

                content {
                  search_string         = var.rate_limit_path_prefix
                  positional_constraint = "STARTS_WITH"

                  field_to_match {
                    uri_path {}
                  }

                  text_transformation {
                    priority = 0
                    type     = "LOWERCASE"
                  }
                }
              }

              dynamic "not_statement" {
                for_each = !rule.value.use_path_prefix && rule.value.skip_allowed_ips ? [1] : []

                content {
                  statement {
                    label_match_statement {
                      scope = "LABEL"
                      key   = local.allowed_ip_label_key
                    }
                  }
                }
              }

              dynamic "and_statement" {
                for_each = rule.value.use_path_prefix && rule.value.skip_allowed_ips ? [1] : []

                content {
                  statement {
                    byte_match_statement {
                      search_string         = var.rate_limit_path_prefix
                      positional_constraint = "STARTS_WITH"

                      field_to_match {
                        uri_path {}
                      }

                      text_transformation {
                        priority = 0
                        type     = "LOWERCASE"
                      }
                    }
                  }

                  statement {
                    not_statement {
                      statement {
                        label_match_statement {
                          scope = "LABEL"
                          key   = local.allowed_ip_label_key
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.name}-${rule.key}"
        sampled_requests_enabled   = var.enable_sampled_requests
      }
    }
  }

  # AWS managed rule groups, always on. Written out (not generated) so that each group is visible to the policy scanners.
  rule {
    name     = "aws-common"
    priority = local.priorities.common

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-aws-common"
      sampled_requests_enabled   = var.enable_sampled_requests
    }
  }

  rule {
    name     = "aws-known-bad-inputs"
    priority = local.priorities.known_bad_inputs

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-aws-known-bad-inputs"
      sampled_requests_enabled   = var.enable_sampled_requests
    }
  }

  rule {
    name     = "aws-ip-reputation"
    priority = local.priorities.ip_reputation

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-aws-ip-reputation"
      sampled_requests_enabled   = var.enable_sampled_requests
    }
  }

  rule {
    name     = "aws-sqli"
    priority = local.priorities.sqli

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-aws-sqli"
      sampled_requests_enabled   = var.enable_sampled_requests
    }
  }

  # AnonymousIp is mandatory in RF04 (VPN, proxies, Tor, hosting providers): it has no toggle.
  rule {
    name     = "aws-anonymous-ip"
    priority = local.priorities.anonymous_ip

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAnonymousIpList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-aws-anonymous-ip"
      sampled_requests_enabled   = var.enable_sampled_requests
    }
  }

  # Optional managed group: Bot Control (enable_bot_control).
  dynamic "rule" {
    for_each = local.optional_managed_rule_groups

    content {
      name     = rule.key
      priority = rule.value.priority

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.group
          vendor_name = "AWS"

          dynamic "managed_rule_group_configs" {
            for_each = rule.value.bot_control ? [1] : []

            content {
              aws_managed_rules_bot_control_rule_set {
                inspection_level = "COMMON"
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.name}-${rule.key}"
        sampled_requests_enabled   = var.enable_sampled_requests
      }
    }
  }

  tags = merge(var.tags, { Name = local.name })
}

# Regional resources (API Gateway REST stages) only. A CloudFront distribution references the web ACL through its
# web_acl_id, so the module never associates anything for the CLOUDFRONT scope. Keyed by static caller-chosen names
# (the ARNs are usually unknown until apply): reordering or adding an entry never recreates another association.
resource "aws_wafv2_web_acl_association" "this" {
  for_each = var.associated_resource_arns

  resource_arn = each.value
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

check "kms_key_in_log_group_region" {
  assert {
    condition     = try(split(":", var.kms_key_arn)[3], "") == data.aws_region.current.region
    error_message = "kms_key_arn must be in the region of the WAF log group (the region of the provider passed to the module)."
  }
}

check "cloudfront_scope_in_us_east_1" {
  assert {
    condition     = var.scope != "CLOUDFRONT" || data.aws_region.current.region == "us-east-1"
    error_message = "A CLOUDFRONT web ACL must be created with a us-east-1 provider (providers = { aws = aws.us_east_1 })."
  }
}

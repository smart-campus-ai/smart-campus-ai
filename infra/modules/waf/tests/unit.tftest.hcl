mock_provider "aws" {
  # Fake documentation account ID, used only to keep names and conditions predictable.
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "eu-west-3"
    }
  }

  # The mock returns random strings for computed attributes, which aws_cloudwatch_log_resource_policy rejects as
  # invalid JSON. The invariants are asserted on the document arguments (known at plan), not on the JSON.
  override_data {
    target = data.aws_iam_policy_document.log_delivery
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # Computed ARNs consumed by other resources (policy document, logging configuration, rules, association).
  override_resource {
    target = aws_wafv2_web_acl.this
    values = {
      id  = "00000000-0000-0000-0000-000000000000"
      arn = "arn:aws:wafv2:eu-west-3:123456789012:regional/webacl/sc-dev-waf-regional/00000000-0000-0000-0000-000000000000"
    }
  }

  override_resource {
    target = aws_wafv2_ip_set.this
    values = {
      arn = "arn:aws:wafv2:eu-west-3:123456789012:regional/ipset/sc-dev-waf-regional-ip/00000000-0000-0000-0000-000000000000"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.waf
    values = {
      arn = "arn:aws:logs:eu-west-3:123456789012:log-group:aws-waf-logs-sc-dev-regional"
    }
  }
}

variables {
  name_prefix        = "sc-dev"
  scope              = "REGIONAL"
  kms_key_arn        = "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000001"
  log_retention_days = 14
  rate_limit_per_ip  = 1000
}

# RF04-AC1: CLOUDFRONT web ACL with the managed groups and the body size limit, never associated by the module
run "rf04_ac1_cloudfront_web_acl_rules" {
  command = plan

  variables {
    scope       = "CLOUDFRONT"
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000002"
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-1"
    }
  }

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "CLOUDFRONT" && aws_wafv2_web_acl.this.name == "sc-dev-waf-cloudfront"
    error_message = "The web ACL must have the CLOUDFRONT scope and be named <prefix>-waf-cloudfront."
  }

  assert {
    condition = alltrue([
      for group in [
        "AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet",
        "AWSManagedRulesAmazonIpReputationList", "AWSManagedRulesAnonymousIpList", "AWSManagedRulesSQLiRuleSet",
      ] : contains([for r in aws_wafv2_web_acl.this.rule : try(one(one(r.statement).managed_rule_group_statement).name, "")], group)
    ])
    error_message = "The web ACL must contain the Common, KnownBadInputs, IpReputation, AnonymousIp and SQLi managed groups."
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "body-size-limit" && length(one(r.action).block) == 1 &&
      one(one(r.statement).size_constraint_statement).comparison_operator == "GT" &&
      one(one(r.statement).size_constraint_statement).size == 8192
    ])
    error_message = "The web ACL must block bodies larger than max_body_size_bytes."
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 0
    error_message = "The module must not associate anything for the CLOUDFRONT scope."
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf.name == "aws-waf-logs-sc-dev-cloudfront"
    error_message = "The CLOUDFRONT log group must be aws-waf-logs-<prefix>-cloudfront."
  }
}

# RF04-AC2: REGIONAL web ACL with the same groups and body size limit, associated with the API stage
run "rf04_ac2_regional_web_acl_associated_with_stage" {
  command = plan

  variables {
    associated_resource_arns = { api = "arn:aws:apigateway:eu-west-3::/restapis/abc123/stages/live" }
  }

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "REGIONAL" && aws_wafv2_web_acl.this.name == "sc-dev-waf-regional"
    error_message = "The web ACL must have the REGIONAL scope and be named <prefix>-waf-regional."
  }

  assert {
    condition = alltrue([
      for group in [
        "AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet",
        "AWSManagedRulesAmazonIpReputationList", "AWSManagedRulesAnonymousIpList", "AWSManagedRulesSQLiRuleSet",
      ] : contains([for r in aws_wafv2_web_acl.this.rule : try(one(one(r.statement).managed_rule_group_statement).name, "")], group)
    ])
    error_message = "The web ACL must contain the same managed groups as the CLOUDFRONT one."
  }

  assert {
    condition     = contains([for r in aws_wafv2_web_acl.this.rule : r.name], "body-size-limit")
    error_message = "The web ACL must contain the body size limit."
  }

  assert {
    condition     = keys(aws_wafv2_web_acl_association.this) == ["api"] && aws_wafv2_web_acl_association.this["api"].resource_arn == "arn:aws:apigateway:eu-west-3::/restapis/abc123/stages/live"
    error_message = "The web ACL must be associated with the given API stage."
  }
}

# RF04-AC3: requests carrying the same Authorization header are counted together and answered with a 429
run "rf04_ac3_rate_limit_per_authorization_header" {
  command = plan

  variables {
    rate_limit_per_authorization = 300
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "rate-limit-authorization" &&
      one(one(r.statement).rate_based_statement).aggregate_key_type == "CUSTOM_KEYS" &&
      one(one(r.statement).rate_based_statement).limit == 300 &&
      anytrue([for k in one(one(r.statement).rate_based_statement).custom_key : one(k.header).name == "authorization"])
    ])
    error_message = "The per-user rule must aggregate on the Authorization header with the configured limit."
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "rate-limit-authorization" && one(one(one(r.action).block).custom_response).response_code == 429
    ])
    error_message = "The per-user rule must answer with a 429."
  }
}

# RF04-AC3: the per-user rule is off unless a limit is given
run "rf04_ac3_rate_limit_per_authorization_off_by_default" {
  command = plan

  assert {
    condition     = !contains([for r in aws_wafv2_web_acl.this.rule : r.name], "rate-limit-authorization")
    error_message = "The per-user rule must not exist without rate_limit_per_authorization."
  }
}

# RF04-AC4: requests from the same IP are counted together over the window and answered with a 429
run "rf04_ac4_rate_limit_per_ip" {
  command = plan

  variables {
    rate_limit_per_ip         = 500
    rate_limit_window_seconds = 120
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "rate-limit-ip" &&
      one(one(r.statement).rate_based_statement).aggregate_key_type == "IP" &&
      one(one(r.statement).rate_based_statement).limit == 500 &&
      one(one(r.statement).rate_based_statement).evaluation_window_sec == 120
    ])
    error_message = "The per-IP rule must aggregate on the IP with the configured limit and window."
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "rate-limit-ip" &&
      one(one(one(r.action).block).custom_response).response_code == 429 &&
      one(one(one(r.action).block).custom_response).custom_response_body_key == "rate-limited" &&
      one(one(one(one(r.action).block).custom_response).response_header).value == "120"
    ])
    error_message = "The per-IP rule must answer with a 429 JSON body and a Retry-After header equal to the window."
  }

  assert {
    condition     = contains([for b in aws_wafv2_web_acl.this.custom_response_body : b.key], "rate-limited")
    error_message = "The 429 response body must be defined on the web ACL."
  }
}

# RF04-AC4: only the per-user rule is limited to a path; the per-IP rule covers every URL (execute-api included)
run "rf04_ac4_rate_limit_path_prefix_on_per_user_rule_only" {
  command = plan

  variables {
    rate_limit_per_authorization = 300
    rate_limit_path_prefix       = "/api/chat"
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "rate-limit-authorization" &&
      one(one(one(one(r.statement).rate_based_statement).scope_down_statement).byte_match_statement).search_string == "/api/chat"
    ])
    error_message = "The per-user rule must be scoped down to the configured path prefix."
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "rate-limit-ip" && length(one(one(r.statement).rate_based_statement).scope_down_statement) == 0
    ])
    error_message = "The per-IP rule must not be filtered by the path prefix."
  }
}

# RF04-AC5: the regional ACL carries the rate rules and is associated with the stage, so the execute-api URL is covered
run "rf04_ac5_execute_api_covered_by_regional_rate_rules" {
  command = plan

  variables {
    rate_limit_per_authorization = 300
    associated_resource_arns     = { api = "arn:aws:apigateway:eu-west-3::/restapis/abc123/stages/live" }
  }

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "REGIONAL" && length(aws_wafv2_web_acl_association.this) == 1
    error_message = "The regional web ACL must be associated with the API stage."
  }

  assert {
    condition     = alltrue([for n in ["rate-limit-ip", "rate-limit-authorization"] : contains([for r in aws_wafv2_web_acl.this.rule : r.name], n)])
    error_message = "The regional web ACL must carry both rate rules."
  }

  assert {
    condition     = aws_wafv2_web_acl_association.this["api"].web_acl_arn == aws_wafv2_web_acl.this.arn
    error_message = "The association must reference the module web ACL."
  }
}

# RF04-AC6: managed groups enforce (no count override), requests pass by default and bad ones are blocked by the groups
run "rf04_ac6_managed_groups_enforced" {
  command = plan

  assert {
    condition     = length(aws_wafv2_web_acl.this.default_action) == 1 && length(one(aws_wafv2_web_acl.this.default_action).allow) == 1
    error_message = "The default action must be allow; blocking is done by the rules."
  }

  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.this.rule :
      length(one(r.override_action).none) == 1
      if length(r.override_action) > 0
    ])
    error_message = "Managed rule groups must keep their own actions (override_action none), not count."
  }

  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.this.rule :
      length(one(one(r.statement).managed_rule_group_statement).rule_action_override) == 0
      if length(one(r.statement).managed_rule_group_statement) > 0
    ])
    error_message = "No managed rule may be overridden."
  }

  assert {
    condition     = alltrue([for r in aws_wafv2_web_acl.this.rule : length(r.override_action) == 1 || length(r.action) == 1])
    error_message = "Every rule must have exactly one action or override action."
  }
}

# RF04-AC7: logs go to a KMS-encrypted aws-waf-logs-* group with a retention
run "rf04_ac7_log_group_encrypted_with_retention" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.waf.name == "aws-waf-logs-sc-dev-regional" && startswith(aws_cloudwatch_log_group.waf.name, "aws-waf-logs-")
    error_message = "The log group must be named aws-waf-logs-<prefix>-<scope>."
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf.kms_key_id == var.kms_key_arn
    error_message = "The log group must be encrypted with the KMS key given in kms_key_arn."
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf.retention_in_days == 14
    error_message = "The log group retention must follow log_retention_days."
  }
}

# RF04-AC7: the web ACL logs to the group and never writes the Authorization or Cookie header
run "rf04_ac7_logging_redacts_authorization_and_cookie" {
  command = plan

  assert {
    condition     = toset(aws_wafv2_web_acl_logging_configuration.this.log_destination_configs) == toset([aws_cloudwatch_log_group.waf.arn])
    error_message = "The logging configuration must target the module log group."
  }

  assert {
    condition     = aws_wafv2_web_acl_logging_configuration.this.resource_arn == aws_wafv2_web_acl.this.arn
    error_message = "The logging configuration must be attached to the module web ACL."
  }

  assert {
    condition = toset([
      for f in aws_wafv2_web_acl_logging_configuration.this.redacted_fields : one(f.single_header).name
    ]) == toset(["authorization", "cookie"])
    error_message = "The authorization and cookie headers must be redacted from the WAF logs."
  }
}

# RF04-AC7: the Cognito callback code (?code=) is redacted from the CloudFront logs; the regional ACL keeps it
run "rf04_ac7_logging_redacts_query_string_on_cloudfront" {
  command = plan

  variables {
    scope       = "CLOUDFRONT"
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000002"
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-1"
    }
  }

  assert {
    condition     = anytrue([for f in aws_wafv2_web_acl_logging_configuration.this.redacted_fields : length(f.query_string) == 1])
    error_message = "The query string must be redacted from the CLOUDFRONT WAF logs."
  }
}

run "rf04_ac7_logging_keeps_query_string_on_regional" {
  command = plan

  assert {
    condition     = !anytrue([for f in aws_wafv2_web_acl_logging_configuration.this.redacted_fields : length(f.query_string) == 1])
    error_message = "Only the CLOUDFRONT scope redacts the query string."
  }
}

# RF04-AC7: metrics and sampled requests are on for the web ACL and every rule
run "rf04_ac7_visibility_metrics_enabled" {
  command = plan

  variables {
    rate_limit_per_authorization = 300
    enable_bot_control           = true
    blocked_ip_addresses         = ["198.51.100.0/24"]
  }

  assert {
    condition = alltrue([
      for v in aws_wafv2_web_acl.this.visibility_config :
      v.cloudwatch_metrics_enabled && v.sampled_requests_enabled
    ])
    error_message = "The web ACL must publish metrics and sampled requests."
  }

  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.this.rule :
      alltrue([for v in r.visibility_config : v.cloudwatch_metrics_enabled && v.sampled_requests_enabled])
    ])
    error_message = "Every rule must publish metrics and sampled requests."
  }
}

# RF04-AC7: the log delivery policy is scoped to this log group, the logs ARNs of this account and region, and this account
run "rf04_ac7_log_resource_policy_prevents_confused_deputy" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_resource_policy.waf) == 1
    error_message = "The log resource policy must be created by default."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.log_delivery.statement :
      s.effect == "Allow" &&
      toset(s.actions) == toset(["logs:CreateLogStream", "logs:PutLogEvents"]) &&
      toset(s.resources) == toset(["arn:aws:logs:eu-west-3:123456789012:log-group:aws-waf-logs-sc-dev-regional:*"]) &&
      alltrue([for p in s.principals : p.type == "Service" && p.identifiers == toset(["delivery.logs.amazonaws.com"])])
    ])
    error_message = "The policy must only let the log delivery service create streams and put events on the module log group."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.log_delivery.statement :
      anytrue([for c in s.condition : c.variable == "aws:SourceArn" && c.test == "ArnLike" && contains(c.values, "arn:aws:logs:eu-west-3:123456789012:*")]) &&
      anytrue([for c in s.condition : c.variable == "aws:SourceAccount" && c.test == "StringEquals" && contains(c.values, "123456789012")])
    ])
    error_message = "The policy must carry aws:SourceArn (logs ARNs of this account and region) and aws:SourceAccount conditions."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.log_delivery.statement :
      !anytrue([for a in s.actions : a == "*" || endswith(a, ":*")]) && !contains(s.resources, "*")
    ])
    error_message = "The policy must not use wildcard actions or a wildcard resource."
  }
}

run "rf04_ac7_log_resource_policy_can_be_disabled" {
  command = plan

  variables {
    enable_log_resource_policy = false
  }

  assert {
    condition     = length(aws_cloudwatch_log_resource_policy.waf) == 0
    error_message = "enable_log_resource_policy = false must not create the policy."
  }
}

# IP lists: IPv4 and IPv6 are split into separate sets, a deny is evaluated before an allow, and both before the rest
run "rf04_ac6_ip_sets_split_by_family_and_ordered" {
  command = plan

  variables {
    allowed_ip_addresses = ["192.0.2.0/24", "2001:db8::/32"]
    blocked_ip_addresses = ["198.51.100.0/24"]
  }

  assert {
    condition     = toset(keys(aws_wafv2_ip_set.this)) == toset(["allow-ipv4", "allow-ipv6", "block-ipv4"])
    error_message = "One IP set per non-empty family and action is expected."
  }

  assert {
    condition     = aws_wafv2_ip_set.this["allow-ipv6"].ip_address_version == "IPV6" && aws_wafv2_ip_set.this["allow-ipv4"].ip_address_version == "IPV4"
    error_message = "IP sets must carry the right address family."
  }

  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.this.rule :
      length(one(r.action).allow) == 0 && length(one(r.action).count) == 1 && one(r.rule_label).name == "allowed-ip"
      if startswith(r.name, "ip-allow-")
    ])
    error_message = "An allowed address must be counted and labelled, never allowed (an allow would skip every later rule)."
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "ip-block-ipv4" && length(one(r.action).block) == 1 && r.priority < min([for o in aws_wafv2_web_acl.this.rule : o.priority if startswith(o.name, "ip-allow-")]...)
    ])
    error_message = "A blocked address must be denied before the allow list is evaluated."
  }

  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.priority < min([for o in aws_wafv2_web_acl.this.rule : o.priority if !startswith(o.name, "ip-")]...)
      if startswith(r.name, "ip-")
    ])
    error_message = "IP list rules must be evaluated before every other rule."
  }
}

# An allowed IP skips the rate rules only (label), never the body size limit nor the managed groups
run "rf04_ac6_allowed_ip_skips_rate_rules_only" {
  command = plan

  variables {
    allowed_ip_addresses         = ["192.0.2.0/24"]
    rate_limit_per_authorization = 300
    rate_limit_path_prefix       = "/api/chat"
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      one(one(one(one(one(one(r.statement).rate_based_statement).scope_down_statement).not_statement).statement).label_match_statement).key == "awswaf:123456789012:webacl:sc-dev-waf-regional:allowed-ip"
      if r.name == "rate-limit-ip"
    ])
    error_message = "The per-IP rule must skip requests carrying the allowed-ip label."
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      length(one(one(one(r.statement).rate_based_statement).scope_down_statement).and_statement) == 1
      if r.name == "rate-limit-authorization"
    ])
    error_message = "The per-user rule must combine the path prefix and the allowed-ip exclusion."
  }

  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.this.rule :
      length(r.rule_label) == 0 && length(one(r.action).count) == 0
      if contains(["body-size-limit", "aws-common", "aws-known-bad-inputs", "aws-ip-reputation", "aws-sqli"], r.name) && length(r.action) > 0
    ])
    error_message = "The body size limit and the managed groups must still apply to allowed addresses."
  }
}

# Associations are keyed by static names, so a reorder never recreates them
run "rf04_ac2_associations_keyed_by_static_names" {
  command = plan

  variables {
    associated_resource_arns = {
      api   = "arn:aws:apigateway:eu-west-3::/restapis/abc123/stages/live"
      other = "arn:aws:apigateway:eu-west-3::/restapis/def456/stages/live"
    }
  }

  assert {
    condition     = toset(keys(aws_wafv2_web_acl_association.this)) == toset(["api", "other"])
    error_message = "Associations must be keyed by the caller-chosen names."
  }
}

run "rf04_ac6_no_ip_set_without_addresses" {
  command = plan

  assert {
    condition     = length(aws_wafv2_ip_set.this) == 0 && !anytrue([for r in aws_wafv2_web_acl.this.rule : startswith(r.name, "ip-")])
    error_message = "No IP set or IP rule may exist without addresses."
  }
}

# Optional managed groups
run "rf04_ac2_optional_groups_toggles" {
  command = plan

  variables {
    enable_anonymous_ip_list = false
    enable_bot_control       = true
  }

  assert {
    condition     = !contains([for r in aws_wafv2_web_acl.this.rule : r.name], "aws-anonymous-ip")
    error_message = "enable_anonymous_ip_list = false must remove the AnonymousIp group."
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "aws-bot-control" &&
      one(one(r.statement).managed_rule_group_statement).name == "AWSManagedRulesBotControlRuleSet"
    ])
    error_message = "enable_bot_control = true must add the Bot Control group."
  }
}

run "rf04_ac2_bot_control_off_by_default" {
  command = plan

  assert {
    condition     = !contains([for r in aws_wafv2_web_acl.this.rule : r.name], "aws-bot-control")
    error_message = "Bot Control must be off by default."
  }
}

# Rule priorities and names are unique, otherwise AWS WAF refuses the web ACL
run "rf04_ac2_rule_priorities_and_names_unique" {
  command = plan

  variables {
    rate_limit_per_authorization = 300
    enable_bot_control           = true
    allowed_ip_addresses         = ["192.0.2.0/24", "2001:db8::/32"]
    blocked_ip_addresses         = ["198.51.100.0/24", "2001:db8:1::/48"]
  }

  assert {
    condition     = length(toset([for r in aws_wafv2_web_acl.this.rule : r.priority])) == length(aws_wafv2_web_acl.this.rule)
    error_message = "Rule priorities must be unique."
  }

  assert {
    condition     = length(toset([for r in aws_wafv2_web_acl.this.rule : r.name])) == length(aws_wafv2_web_acl.this.rule)
    error_message = "Rule names must be unique."
  }
}

# Variable validations
run "rf04_validation_scope_rejected" {
  command = plan

  variables {
    scope = "GLOBAL"
  }

  expect_failures = [var.scope]
}

run "rf04_validation_name_prefix_rejected" {
  command = plan

  variables {
    name_prefix = "SC_Dev"
  }

  expect_failures = [var.name_prefix]
}

run "rf04_validation_kms_key_arn_rejected" {
  command = plan

  variables {
    kms_key_arn = "alias/sc-logs"
  }

  expect_failures = [var.kms_key_arn]
}

run "rf04_validation_log_retention_rejected" {
  command = plan

  variables {
    log_retention_days = 10
  }

  expect_failures = [var.log_retention_days]
}

run "rf04_validation_rate_limit_per_ip_rejected" {
  command = plan

  variables {
    rate_limit_per_ip = 0
  }

  expect_failures = [var.rate_limit_per_ip]
}

run "rf04_validation_rate_limit_per_authorization_rejected" {
  command = plan

  variables {
    rate_limit_per_authorization = -1
  }

  expect_failures = [var.rate_limit_per_authorization]
}

run "rf04_validation_rate_limit_window_rejected" {
  command = plan

  variables {
    rate_limit_window_seconds = 30
  }

  expect_failures = [var.rate_limit_window_seconds]
}

run "rf04_validation_rate_limit_path_prefix_rejected" {
  command = plan

  variables {
    rate_limit_path_prefix = "api/Chat"
  }

  expect_failures = [var.rate_limit_path_prefix]
}

run "rf04_validation_max_body_size_rejected" {
  command = plan

  variables {
    max_body_size_bytes = 65536
  }

  expect_failures = [var.max_body_size_bytes]
}

run "rf04_validation_allowed_ip_addresses_rejected" {
  command = plan

  variables {
    allowed_ip_addresses = ["192.0.2.1"]
  }

  expect_failures = [var.allowed_ip_addresses]
}

run "rf04_validation_blocked_ip_addresses_rejected" {
  command = plan

  variables {
    blocked_ip_addresses = ["0.0.0.0/0"]
  }

  expect_failures = [var.blocked_ip_addresses]
}

run "rf04_validation_association_refused_for_cloudfront" {
  command = plan

  variables {
    scope                    = "CLOUDFRONT"
    kms_key_arn              = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000002"
    associated_resource_arns = { api = "arn:aws:apigateway:eu-west-3::/restapis/abc123/stages/live" }
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-1"
    }
  }

  expect_failures = [var.associated_resource_arns]
}

run "rf04_validation_association_arn_rejected" {
  command = plan

  variables {
    associated_resource_arns = { api = "not-an-arn" }
  }

  expect_failures = [var.associated_resource_arns]
}

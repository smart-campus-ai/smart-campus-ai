data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
  scope_slug = lower(var.scope)

  name = "${var.name_prefix}-waf-${local.scope_slug}"

  # An allowed address is labelled instead of being let through: it only skips the rate-based rules, every other
  # rule (body size, managed groups) still inspects it. The label key is <namespace>:<label name>, with the web ACL
  # namespace awswaf:<account id>:webacl:<web ACL name>.
  allowed_ip_label_name = "allowed-ip"
  allowed_ip_label_key  = "awswaf:${local.account_id}:webacl:${local.name}:${local.allowed_ip_label_name}"
  has_allowed_ips       = length(var.allowed_ip_addresses) > 0

  # AWS WAF only delivers to CloudWatch Logs groups whose name starts with "aws-waf-logs-".
  log_group_name = "aws-waf-logs-${var.name_prefix}-${local.scope_slug}"

  # Headers whose value never reaches the logs.
  redacted_headers = toset(["authorization", "cookie"])

  rate_limited_body_key = "rate-limited"

  # Evaluation order (lowest first): explicit deny (10), allow-list labelling (20), body size, rate limits, managed groups.
  priorities = {
    body_size          = 30
    rate_ip            = 40
    rate_authorization = 41
    common             = 50
    known_bad_inputs   = 60
    ip_reputation      = 70
    anonymous_ip       = 80
    sqli               = 90
    bot_control        = 100
  }

  ip_set_candidates = {
    "block-ipv4" = { action = "block", version = "IPV4", priority = 10, addresses = [for a in var.blocked_ip_addresses : a if !strcontains(a, ":")] }
    "block-ipv6" = { action = "block", version = "IPV6", priority = 11, addresses = [for a in var.blocked_ip_addresses : a if strcontains(a, ":")] }
    "allow-ipv4" = { action = "label", version = "IPV4", priority = 20, addresses = [for a in var.allowed_ip_addresses : a if !strcontains(a, ":")] }
    "allow-ipv6" = { action = "label", version = "IPV6", priority = 21, addresses = [for a in var.allowed_ip_addresses : a if strcontains(a, ":")] }
  }

  # Only the sets that have addresses: AWS WAF refuses an empty IP set.
  ip_sets = { for key, set in local.ip_set_candidates : key => set if length(set.addresses) > 0 }

  rate_rule_candidates = {
    "rate-limit-ip" = {
      enabled          = true
      priority         = local.priorities.rate_ip
      limit            = var.rate_limit_per_ip
      by_authorization = false
      use_path_prefix  = false # the per-IP limit protects every URL, whichever path or URL is used
    }
    "rate-limit-authorization" = {
      enabled          = var.rate_limit_per_authorization != null
      priority         = local.priorities.rate_authorization
      limit            = coalesce(var.rate_limit_per_authorization, var.rate_limit_per_ip)
      by_authorization = true
      use_path_prefix  = var.rate_limit_path_prefix != null
    }
  }

  # Per rule, the conditions that narrow it down: the optional path prefix (per-user rule only) and "not an allowed IP".
  rate_rules = {
    for key, rule in local.rate_rule_candidates : key => merge(rule, {
      skip_allowed_ips = local.has_allowed_ips
    }) if rule.enabled
  }

  optional_managed_candidates = {
    "aws-anonymous-ip" = {
      enabled     = var.enable_anonymous_ip_list
      group       = "AWSManagedRulesAnonymousIpList"
      priority    = local.priorities.anonymous_ip
      bot_control = false
    }
    "aws-bot-control" = {
      enabled     = var.enable_bot_control
      group       = "AWSManagedRulesBotControlRuleSet"
      priority    = local.priorities.bot_control
      bot_control = true
    }
  }

  optional_managed_rule_groups = { for key, rule in local.optional_managed_candidates : key => rule if rule.enabled }
}

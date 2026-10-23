variable "name_prefix" {
  description = "Prefix of every resource name, for example \"sc-dev\". The web ACL is named <prefix>-waf-<scope> and the log group aws-waf-logs-<prefix>-<scope>."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "scope" {
  description = "Scope of the web ACL: CLOUDFRONT (the caller must pass a us-east-1 provider as \"aws\") or REGIONAL (API Gateway REST stage, in the region of the provider)."
  type        = string

  validation {
    condition     = contains(["CLOUDFRONT", "REGIONAL"], var.scope)
    error_message = "scope must be CLOUDFRONT or REGIONAL."
  }
}

variable "kms_key_arn" {
  description = "ARN of the customer-managed KMS key (\"logs\" key, EN-14) that encrypts the WAF log group. It must live in the same region as the log group (us-east-1 for CLOUDFRONT) and its key policy must allow the CloudWatch Logs service principal of that region."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-zA-Z-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account id>:key/<id>)."
  }
}

variable "log_retention_days" {
  description = "Retention of the WAF log group, in days (dev 14, prod 90)."
  type        = number

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a retention value supported by CloudWatch Logs (for example 14, 30, 90, 365)."
  }
}

variable "rate_limit_per_ip" {
  description = "Maximum number of requests from one source IP over rate_limit_window_seconds before further requests are blocked with a 429. AWS WAF does not accept a limit below 10."
  type        = number

  validation {
    condition     = var.rate_limit_per_ip >= 10 && var.rate_limit_per_ip <= 2000000000 && floor(var.rate_limit_per_ip) == var.rate_limit_per_ip
    error_message = "rate_limit_per_ip must be a whole number between 10 and 2000000000."
  }
}

variable "rate_limit_per_authorization" {
  description = "Maximum number of requests carrying the same Authorization header (per user) over rate_limit_window_seconds before further requests are blocked with a 429. null disables the per-user rule. Meant for the REGIONAL ACL of the API."
  type        = number
  default     = null

  validation {
    condition     = var.rate_limit_per_authorization == null || (coalesce(var.rate_limit_per_authorization, 10) >= 10 && coalesce(var.rate_limit_per_authorization, 10) <= 2000000000 && floor(coalesce(var.rate_limit_per_authorization, 10)) == coalesce(var.rate_limit_per_authorization, 10))
    error_message = "rate_limit_per_authorization must be null or a whole number between 10 and 2000000000."
  }
}

variable "rate_limit_window_seconds" {
  description = "Evaluation window of the rate-based rules, in seconds. Also returned to throttled clients in the Retry-After header."
  type        = number
  default     = 300

  validation {
    condition     = contains([60, 120, 300, 600], var.rate_limit_window_seconds)
    error_message = "rate_limit_window_seconds must be 60, 120, 300 or 600."
  }
}

variable "rate_limit_path_prefix" {
  description = "Restrict the per-user rule (rate_limit_per_authorization) to requests whose URI path starts with this prefix (for example \"/api/chat\" to protect inference). The per-IP rule is never filtered. null applies the per-user rule to every request. Lowercase, matched case-insensitively. On the REGIONAL ACL, a request sent straight to the execute-api URL may carry the stage name first (\"/<stage>/api/chat\"), so check the prefix against that URL too."
  type        = string
  default     = null

  validation {
    condition     = var.rate_limit_path_prefix == null || can(regex("^/[a-z0-9/_.-]*$", coalesce(var.rate_limit_path_prefix, "invalid")))
    error_message = "rate_limit_path_prefix must start with \"/\" and contain only lowercase letters, digits and the characters / _ . -"
  }
}

variable "max_body_size_bytes" {
  description = "Requests with a body larger than this are blocked. Capped at 8192 bytes; the default inspection size of AWS WAF is 16 KB on CloudFront and API Gateway, and the 8 KB block is also covered by the SizeRestrictions_BODY rule of the Common group."
  type        = number
  default     = 8192

  validation {
    condition     = var.max_body_size_bytes >= 1 && var.max_body_size_bytes <= 8192 && floor(var.max_body_size_bytes) == var.max_body_size_bytes
    error_message = "max_body_size_bytes must be a whole number between 1 and 8192."
  }
}

variable "enable_bot_control" {
  description = "Add the AWSManagedRulesBotControlRuleSet group (COMMON inspection level). Billed per request on top of the web ACL, hence off by default."
  type        = bool
  default     = false
}

variable "allowed_ip_addresses" {
  description = "IPv4 and IPv6 CIDR blocks that skip the rate-based rules only (they are labelled, not allowed): the body size limit and the managed groups (SQLi, KnownBadInputs...) still apply. Meant for a trusted load-test source; keep it empty in prod (the module has no environment variable to enforce it, the stack tfvars of prod must leave it empty). Prefix length 0 is refused by AWS WAF."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_ip_addresses : can(cidrhost(cidr, 0)) && !endswith(cidr, "/0")])
    error_message = "Every allowed_ip_addresses entry must be an IPv4 or IPv6 CIDR block with a prefix length of at least 1 (for example 192.0.2.0/24 or 2001:db8::/32)."
  }
}

variable "blocked_ip_addresses" {
  description = "IPv4 and IPv6 CIDR blocks that are always blocked. Evaluated before allowed_ip_addresses, so a deny wins. Prefix length 0 is refused by AWS WAF."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.blocked_ip_addresses : can(cidrhost(cidr, 0)) && !endswith(cidr, "/0")])
    error_message = "Every blocked_ip_addresses entry must be an IPv4 or IPv6 CIDR block with a prefix length of at least 1 (for example 198.51.100.0/24 or 2001:db8::/32)."
  }
}

variable "associated_resource_arns" {
  description = "ARNs of the regional resources (API Gateway REST stages) to associate with the web ACL, keyed by a static name of your choice (for example { api = aws_api_gateway_stage.this.arn }). Static keys keep an association from being recreated when the map changes. REGIONAL scope only: a CloudFront distribution references the ACL through its web_acl_id."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for arn in values(var.associated_resource_arns) : can(regex("^arn:aws(-[a-z]+)*:apigateway:[a-z0-9-]+::/restapis/[a-z0-9]+/stages/[A-Za-z0-9_-]+$", arn))])
    error_message = "Every associated_resource_arns value must be an API Gateway REST stage ARN (arn:<partition>:apigateway:<region>::/restapis/<id>/stages/<stage>)."
  }

  validation {
    condition     = var.scope == "REGIONAL" || length(var.associated_resource_arns) == 0
    error_message = "associated_resource_arns is only supported with scope = REGIONAL; attach a CLOUDFRONT web ACL through the distribution web_acl_id."
  }
}

variable "enable_log_resource_policy" {
  description = "Create the CloudWatch Logs resource policy that lets AWS WAF deliver to the log group, restricted to the logs ARNs of this account and region (aws:SourceArn, as documented for WAF log delivery) and to this account (aws:SourceAccount). Disable it only if the policy is managed elsewhere: an account holds at most 10 such policies per region."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

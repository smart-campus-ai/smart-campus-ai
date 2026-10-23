variable "name_prefix" {
  description = "Prefix of every resource name, in the form sc-<env> (for example \"sc-dev\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "kms_key_arn" {
  description = "ARN of the customer-managed KMS key (EN-14, edge domain) used for the default SSE-KMS encryption of the bucket. Its key policy must let the CloudFront service principal (cloudfront.amazonaws.com) call kms:Decrypt and kms:GenerateDataKey* with an aws:SourceArn condition on the distribution (or on the distributions of the account), otherwise OAC reads fail."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:<partition>:kms:<region>:<account id>:key/<key id>), not an alias."
  }
}

variable "content_security_policy" {
  description = "Value of the Content-Security-Policy response header, aligned with SE (SPA sources, Cognito endpoint). It must contain frame-ancestors 'none'."
  type        = string

  validation {
    condition     = length(trimspace(var.content_security_policy)) > 0 && can(regex("frame-ancestors\\s+'none'", var.content_security_policy))
    error_message = "content_security_policy must be non-empty and contain frame-ancestors 'none'."
  }

  validation {
    condition     = !can(regex("[\\r\\n]", var.content_security_policy))
    error_message = "content_security_policy must be a single line."
  }
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 (North America and Europe) is enough for a campus audience in France."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "web_acl_id" {
  description = "ARN of the CLOUDFRONT-scope WAFv2 web ACL (us-east-1, RF04) attached to the distribution. Null leaves the distribution without WAF."
  type        = string
  default     = null

  validation {
    condition     = var.web_acl_id == null || can(regex("^arn:aws(-[a-z]+)*:wafv2:us-east-1:[0-9]{12}:global/webacl/[^/]+/[^/]+$", coalesce(var.web_acl_id, "invalid")))
    error_message = "web_acl_id must be the ARN of a CLOUDFRONT-scope WAFv2 web ACL (arn:<partition>:wafv2:us-east-1:<account id>:global/webacl/<name>/<id>)."
  }
}

variable "logging_bucket_name" {
  description = "Name of an existing bucket that receives the CloudFront standard logs and the S3 server access logs of the site bucket. Null disables both. The bucket must be encrypted, have a log retention and allow the CloudFront and S3 logging services to write to it (CloudFront standard logging needs ACLs enabled on the target)."
  type        = string
  default     = null

  validation {
    condition     = var.logging_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", coalesce(var.logging_bucket_name, "invalid")))
    error_message = "logging_bucket_name must be a valid S3 bucket name (3 to 63 characters: lowercase letters, digits, dots and hyphens)."
  }
}

variable "api_origin_domain_name" {
  description = "Domain name of the API Gateway REST API origin (for example \"abc123.execute-api.eu-west-3.amazonaws.com\", EN-33). When set, the \"/api/*\" behaviour is created with caching disabled and the Authorization header forwarded. Null serves the SPA only."
  type        = string
  default     = null

  validation {
    condition     = var.api_origin_domain_name == null || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", coalesce(var.api_origin_domain_name, "invalid")))
    error_message = "api_origin_domain_name must be a bare host name (no scheme, no path)."
  }
}

variable "api_origin_path" {
  description = "Stage path prepended to the requests sent to the API origin (for example \"/live\"). Empty for none."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^(/[A-Za-z0-9._~-]+)?$", var.api_origin_path))
    error_message = "api_origin_path must be empty or a single path segment starting with a slash, without a trailing slash."
  }
}

variable "aliases" {
  description = "Alternate domain names (CNAMEs) of the distribution. Empty while no custom domain exists (ADR-0003); requires acm_certificate_arn when set."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.aliases : can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", a))])
    error_message = "Every alias must be a lowercase host name."
  }

  validation {
    condition     = (length(var.aliases) > 0) == (var.acm_certificate_arn != null)
    error_message = "aliases and acm_certificate_arn must be set together or left empty together."
  }
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate (us-east-1) for aliases. Null keeps the default CloudFront certificate, for which CloudFront enforces its own TLS floor and ignores the minimum protocol version; with a certificate the minimum is TLSv1.2_2021."
  type        = string
  default     = null

  validation {
    condition     = var.acm_certificate_arn == null || can(regex("^arn:aws(-[a-z]+)*:acm:us-east-1:[0-9]{12}:certificate/[A-Za-z0-9-]+$", coalesce(var.acm_certificate_arn, "invalid")))
    error_message = "acm_certificate_arn must be an ACM certificate ARN in us-east-1."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days after which noncurrent object versions (previous SPA builds) are permanently deleted."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days
    error_message = "noncurrent_version_expiration_days must be a whole number greater than or equal to 1."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Number of days after which an incomplete multipart upload is aborted."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1 && floor(var.abort_incomplete_multipart_upload_days) == var.abort_incomplete_multipart_upload_days
    error_message = "abort_incomplete_multipart_upload_days must be a whole number greater than or equal to 1."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

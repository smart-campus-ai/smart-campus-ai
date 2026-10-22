variable "name_prefix" {
  description = "Prefix of every resource name, for example \"sc-dev\". Resources are named \"<name_prefix>-api\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 24 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "openapi_spec" {
  description = "OpenAPI 3 (or Swagger 2) document of the API as a JSON string, rendered by the caller from packages/contracts (the caller injects the Lambda invocation URIs, which point to the \"live\" alias). Every operation must use an aws_proxy integration. The Cognito authorizer (EN-32) is declared in the document itself (components.securitySchemes with x-amazon-apigateway-authorizer). The module adds the body and parameter request validator at the document root."
  type        = string

  validation {
    condition     = can(jsondecode(var.openapi_spec))
    error_message = "openapi_spec must be a valid JSON document."
  }

  validation {
    condition     = try(length(jsondecode(var.openapi_spec).paths) > 0, false)
    error_message = "openapi_spec must define at least one path."
  }

  validation {
    condition = try(alltrue([
      for path, item in jsondecode(var.openapi_spec).paths : alltrue([
        for method, operation in item : try(operation["x-amazon-apigateway-integration"].type == "aws_proxy", false)
        if contains(["get", "put", "post", "delete", "options", "head", "patch", "x-amazon-apigateway-any-method"], lower(method))
      ])
    ]), false)
    error_message = "Every operation of openapi_spec must declare an x-amazon-apigateway-integration of type aws_proxy (Lambda proxy integration)."
  }
}

variable "stage_name" {
  description = "Name of the API stage. It is the path prefix of the invoke URL and the origin path of the CloudFront /api/* behaviour."
  type        = string
  default     = "v1"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]{1,128}$", var.stage_name))
    error_message = "stage_name must be 1 to 128 characters: letters, digits and underscores."
  }
}

variable "kms_key_arn" {
  description = "ARN of the \"logs\" KMS key (EN-14) that encrypts the access and execution log groups. Its key policy must allow the CloudWatch Logs service principal of the region."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-zA-Z-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be the ARN of a KMS key (arn:<partition>:kms:<region>:<account id>:key/<id>), not an alias."
  }
}

variable "log_retention_days" {
  description = "Retention, in days, of the access and execution log groups (dev 14, prod 90). Must be a value accepted by CloudWatch Logs."
  type        = number

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a retention value supported by CloudWatch Logs (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653)."
  }
}

variable "throttling_rate_limit" {
  description = "Steady-state request rate, in requests per second, applied to every method of the stage."
  type        = number

  validation {
    condition     = var.throttling_rate_limit > 0
    error_message = "throttling_rate_limit must be greater than 0."
  }
}

variable "throttling_burst_limit" {
  description = "Burst capacity, in requests, applied to every method of the stage."
  type        = number

  validation {
    condition     = var.throttling_burst_limit > 0 && floor(var.throttling_burst_limit) == var.throttling_burst_limit
    error_message = "throttling_burst_limit must be a whole number greater than 0."
  }
}

variable "method_throttling" {
  description = "Stricter throttling for sensitive methods (chat, ticket creation), keyed by method path \"<resource path without leading slash>/<HTTP method>\", for example \"chat/POST\" or \"tickets/POST\"."
  type = map(object({
    rate_limit  = number
    burst_limit = number
  }))
  default = {}

  validation {
    condition     = alltrue([for path, _ in var.method_throttling : can(regex("^[^/*][^ ]*/(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)$", path))])
    error_message = "Every method_throttling key must look like \"<resource path without leading slash>/<HTTP method>\", for example \"chat/POST\"."
  }

  validation {
    condition = alltrue([
      for _, limits in var.method_throttling :
      limits.rate_limit > 0 && limits.burst_limit > 0 && floor(limits.burst_limit) == limits.burst_limit
    ])
    error_message = "Every method_throttling entry needs a rate_limit greater than 0 and a whole burst_limit greater than 0."
  }
}

variable "web_acl_arn" {
  description = "ARN of the REGIONAL WAF web ACL associated with the stage (RF04, ADR-0004). Null leaves the stage without a web ACL; the platform stack always sets it."
  type        = string
  default     = null

  validation {
    condition     = var.web_acl_arn == null || can(regex("^arn:aws(-[a-z]+)*:wafv2:[a-z0-9-]+:[0-9]{12}:regional/webacl/[A-Za-z0-9_-]+/[0-9a-f-]{36}$", coalesce(var.web_acl_arn, "invalid")))
    error_message = "web_acl_arn must be the ARN of a REGIONAL wafv2 web ACL (arn:<partition>:wafv2:<region>:<account id>:regional/webacl/<name>/<id>)."
  }
}

variable "lambda_integrations" {
  description = "Lambda functions invoked by the API, keyed by a stable name (for example \"tickets\"). function_arn is the unqualified function ARN, qualifier the alias targeted by the integration URIs (\"live\"), routes the \"<HTTP method> <path>\" pairs of the OpenAPI document served by the function (path parameters allowed, ANY for every method). One invoke permission is created per route, limited to that stage, method and path."
  type = map(object({
    function_arn = string
    qualifier    = optional(string, "live")
    routes       = list(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for key, _ in var.lambda_integrations : can(regex("^[a-z][a-z0-9-]{0,39}$", key))])
    error_message = "Every lambda_integrations key must be 1 to 40 characters: lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition = alltrue([
      for _, integration in var.lambda_integrations :
      can(regex("^arn:aws(-[a-z]+)*:lambda:[a-z0-9-]+:[0-9]{12}:function:[a-zA-Z0-9_-]{1,64}$", integration.function_arn))
    ])
    error_message = "Every lambda_integrations function_arn must be an unqualified Lambda function ARN (arn:<partition>:lambda:<region>:<account id>:function:<name>)."
  }

  validation {
    condition     = alltrue([for _, integration in var.lambda_integrations : can(regex("^[a-zA-Z0-9_-]{1,128}$", integration.qualifier))])
    error_message = "Every lambda_integrations qualifier must be a Lambda alias or version name (letters, digits, hyphens and underscores)."
  }

  validation {
    condition = alltrue([
      for _, integration in var.lambda_integrations :
      length(integration.routes) > 0 && alltrue([
        for route in integration.routes : can(regex("^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|ANY) /[^ *]*$", route))
      ])
    ])
    error_message = "Every lambda_integrations entry needs at least one route formatted \"<HTTP method> <path>\" (for example \"POST /tickets\"), with no wildcard character in the path."
  }
}

variable "tags" {
  description = "Extra tags applied to every taggable resource, merged with the provider default_tags."
  type        = map(string)
  default     = {}
}

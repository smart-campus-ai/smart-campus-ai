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
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "eu-west-3"
    }
  }

  # Computed attributes are unknown at plan time; the permissions, the stage and the log groups consume them.
  override_resource {
    target = aws_api_gateway_rest_api.this
    values = {
      id               = "abc123def4"
      arn              = "arn:aws:apigateway:eu-west-3::/restapis/abc123def4"
      execution_arn    = "arn:aws:execute-api:eu-west-3:123456789012:abc123def4"
      root_resource_id = "rootres123"
    }
  }

  override_resource {
    target = aws_api_gateway_deployment.this
    values = {
      id = "dep123"
    }
  }

  override_resource {
    target = aws_api_gateway_stage.this
    values = {
      arn        = "arn:aws:apigateway:eu-west-3::/restapis/abc123def4/stages/v1"
      invoke_url = "https://abc123def4.execute-api.eu-west-3.amazonaws.com/v1"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.access
    values = {
      arn = "arn:aws:logs:eu-west-3:123456789012:log-group:/aws/apigateway/sc-dev-api-v1-access"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.execution
    values = {
      arn = "arn:aws:logs:eu-west-3:123456789012:log-group:API-Gateway-Execution-Logs_abc123def4/v1"
    }
  }
}

variables {
  name_prefix            = "sc-dev"
  kms_key_arn            = "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000001"
  log_retention_days     = 14
  throttling_rate_limit  = 50
  throttling_burst_limit = 100
  web_acl_arn            = "arn:aws:wafv2:eu-west-3:123456789012:regional/webacl/sc-dev-api/11111111-2222-3333-4444-555555555555"

  method_throttling = {
    "chat/POST"    = { rate_limit = 5, burst_limit = 10 }
    "tickets/POST" = { rate_limit = 10, burst_limit = 20 }
  }

  lambda_integrations = {
    tickets = {
      function_arn = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-tickets"
      routes       = ["POST /tickets", "GET /tickets/{id}"]
    }
    chat = {
      function_arn = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-chat"
      routes       = ["POST /chat"]
    }
    kpi = {
      function_arn = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-kpi"
      routes       = ["ANY /admin/{proxy+}"]
    }
  }

  openapi_spec = jsonencode({
    openapi = "3.0.1"
    info    = { title = "smartcampus", version = "1.0.0" }
    paths = {
      "/tickets" = {
        post = {
          "x-amazon-apigateway-integration" = {
            type       = "aws_proxy"
            httpMethod = "POST"
            uri        = "arn:aws:apigateway:eu-west-3:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-tickets:live/invocations"
          }
        }
      }
      "/tickets/{id}" = {
        parameters = [{ name = "id", "in" = "path", required = true, schema = { type = "string" } }]
        get = {
          "x-amazon-apigateway-integration" = {
            type       = "aws_proxy"
            httpMethod = "POST"
            uri        = "arn:aws:apigateway:eu-west-3:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-tickets:live/invocations"
          }
        }
      }
      "/chat" = {
        post = {
          "x-amazon-apigateway-integration" = {
            type       = "aws_proxy"
            httpMethod = "POST"
            uri        = "arn:aws:apigateway:eu-west-3:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-chat:live/invocations"
          }
        }
      }
    }
    components = {
      securitySchemes = {
        cognito = {
          type                             = "apiKey"
          name                             = "Authorization"
          "in"                             = "header"
          "x-amazon-apigateway-authtype"   = "cognito_user_pools"
          "x-amazon-apigateway-authorizer" = { type = "cognito_user_pools", providerARNs = ["arn:aws:cognito-idp:eu-west-3:123456789012:userpool/eu-west-3_example"] }
        }
      }
    }
  })
}

# EN33-AC1: the API is regional and built from the OpenAPI body
run "en33_ac1_regional_api_from_openapi_body" {
  command = plan

  assert {
    condition     = length(one(aws_api_gateway_rest_api.this.endpoint_configuration).types) == 1 && contains(one(aws_api_gateway_rest_api.this.endpoint_configuration).types, "REGIONAL")
    error_message = "The REST API must use the REGIONAL endpoint type."
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.name == "sc-dev-api"
    error_message = "The API name must be <name_prefix>-api."
  }

  assert {
    condition     = toset(keys(jsondecode(aws_api_gateway_rest_api.this.body).paths)) == toset(["/tickets", "/tickets/{id}", "/chat"])
    error_message = "The API body must carry every path of the OpenAPI document."
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.fail_on_warnings == true
    error_message = "OpenAPI import warnings must fail the apply."
  }
}

# EN33-AC1: every operation is a Lambda proxy integration on the "live" alias
run "en33_ac1_every_operation_is_proxy_to_live_alias" {
  command = plan

  assert {
    condition = alltrue([
      for path, item in jsondecode(aws_api_gateway_rest_api.this.body).paths : alltrue([
        for method, operation in item :
        operation["x-amazon-apigateway-integration"].type == "aws_proxy" &&
        endswith(operation["x-amazon-apigateway-integration"].uri, ":live/invocations")
        if contains(["get", "put", "post", "delete", "options", "head", "patch"], method)
      ])
    ])
    error_message = "Every operation must be an aws_proxy integration targeting the live alias."
  }
}

# EN33-AC1: a non-proxy integration is rejected
run "en33_ac1_rejects_non_proxy_integration" {
  command = plan

  variables {
    openapi_spec = jsonencode({
      openapi = "3.0.1"
      info    = { title = "smartcampus", version = "1.0.0" }
      paths = {
        "/tickets" = {
          post = {
            "x-amazon-apigateway-integration" = {
              type       = "aws"
              httpMethod = "POST"
              uri        = "arn:aws:apigateway:eu-west-3:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-tickets:live/invocations"
            }
          }
        }
      }
    })
  }

  expect_failures = [var.openapi_spec]
}

# EN33-AC1: an operation without integration is rejected
run "en33_ac1_rejects_operation_without_integration" {
  command = plan

  variables {
    openapi_spec = jsonencode({
      openapi = "3.0.1"
      info    = { title = "smartcampus", version = "1.0.0" }
      paths   = { "/tickets" = { get = { responses = { "200" = { description = "ok" } } } } }
    })
  }

  expect_failures = [var.openapi_spec]
}

# EN33-AC1: a document without path is rejected
run "en33_ac1_rejects_document_without_paths" {
  command = plan

  variables {
    openapi_spec = jsonencode({ openapi = "3.0.1", paths = {} })
  }

  expect_failures = [var.openapi_spec]
}

# EN33-AC2: body and parameter validation is enforced at the document root
run "en33_ac2_request_validator_body_and_params" {
  command = plan

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body)["x-amazon-apigateway-request-validator"] == "body-and-params"
    error_message = "The body-and-params validator must be the default validator of the API."
  }

  assert {
    condition = alltrue([
      jsondecode(aws_api_gateway_rest_api.this.body)["x-amazon-apigateway-request-validators"]["body-and-params"].validateRequestBody,
      jsondecode(aws_api_gateway_rest_api.this.body)["x-amazon-apigateway-request-validators"]["body-and-params"].validateRequestParameters,
    ])
    error_message = "The validator must validate both the request body and the request parameters."
  }
}

# EN33-AC2: validators declared by the caller are kept, the root validator stays enforced
run "en33_ac2_keeps_caller_validators" {
  command = plan

  variables {
    openapi_spec = jsonencode({
      openapi                                  = "3.0.1"
      info                                     = { title = "smartcampus", version = "1.0.0" }
      "x-amazon-apigateway-request-validator"  = "params-only"
      "x-amazon-apigateway-request-validators" = { params-only = { validateRequestBody = false, validateRequestParameters = true } }
      paths = {
        "/tickets" = {
          post = {
            "x-amazon-apigateway-integration" = {
              type       = "aws_proxy"
              httpMethod = "POST"
              uri        = "arn:aws:apigateway:eu-west-3:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-tickets:live/invocations"
            }
          }
        }
      }
      components = {
        securitySchemes = {
          cognito = { type = "apiKey", name = "Authorization", "in" = "header", "x-amazon-apigateway-authorizer" = { type = "cognito_user_pools" } }
        }
      }
    })
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body)["x-amazon-apigateway-request-validator"] == "body-and-params"
    error_message = "The module validator must replace a weaker root validator."
  }

  assert {
    condition     = toset(keys(jsondecode(aws_api_gateway_rest_api.this.body)["x-amazon-apigateway-request-validators"])) == toset(["body-and-params", "params-only"])
    error_message = "Validators declared by the caller must be kept for method-level use."
  }
}

# EN33-AC3: stage-wide throttling limits
run "en33_ac3_stage_throttling_limits" {
  command = plan

  variables {
    throttling_rate_limit  = 20
    throttling_burst_limit = 40
  }

  assert {
    condition     = aws_api_gateway_method_settings.default.method_path == "*/*"
    error_message = "The default settings must apply to every method of the stage."
  }

  assert {
    condition     = one(aws_api_gateway_method_settings.default.settings).throttling_rate_limit == 20 && one(aws_api_gateway_method_settings.default.settings).throttling_burst_limit == 40
    error_message = "The stage throttling must follow throttling_rate_limit and throttling_burst_limit."
  }
}

# EN33-AC3: sensitive methods have their own limits
run "en33_ac3_sensitive_methods_throttled" {
  command = plan

  assert {
    condition     = toset(keys(aws_api_gateway_method_settings.override)) == toset(["chat/POST", "tickets/POST"])
    error_message = "Chat and ticket creation must have method-level settings."
  }

  assert {
    condition     = one(aws_api_gateway_method_settings.override["chat/POST"].settings).throttling_rate_limit == 5 && one(aws_api_gateway_method_settings.override["chat/POST"].settings).throttling_burst_limit == 10
    error_message = "chat/POST must use its own rate and burst limits."
  }

  assert {
    condition     = one(aws_api_gateway_method_settings.override["tickets/POST"].settings).throttling_rate_limit == 10 && one(aws_api_gateway_method_settings.override["tickets/POST"].settings).throttling_burst_limit == 20
    error_message = "tickets/POST must use its own rate and burst limits."
  }

  assert {
    condition = alltrue([
      for key, setting in aws_api_gateway_method_settings.override :
      one(setting.settings).metrics_enabled == true && one(setting.settings).logging_level == "ERROR" && one(setting.settings).data_trace_enabled == false
    ])
    error_message = "Method-level settings must keep metrics, ERROR logging and no data trace."
  }
}

# EN33-AC3: the stage default settings enable metrics and ERROR-level execution logs without data trace or cache
run "en33_ac3_default_settings_metrics_and_logging" {
  command = plan

  assert {
    condition     = one(aws_api_gateway_method_settings.default.settings).metrics_enabled == true
    error_message = "CloudWatch metrics must be enabled."
  }

  assert {
    condition     = one(aws_api_gateway_method_settings.default.settings).logging_level == "ERROR"
    error_message = "The execution logging level must be ERROR."
  }

  assert {
    condition     = one(aws_api_gateway_method_settings.default.settings).data_trace_enabled == false
    error_message = "Data trace must be disabled: it writes request and response bodies to the logs."
  }

  assert {
    condition     = one(aws_api_gateway_method_settings.default.settings).caching_enabled == false && aws_api_gateway_stage.this.cache_cluster_enabled == false
    error_message = "Response caching must be disabled (per-user responses)."
  }
}

# EN33-AC3: no method-level settings by default
run "en33_ac3_no_override_by_default" {
  command = plan

  variables {
    method_throttling = {}
  }

  assert {
    condition     = length(aws_api_gateway_method_settings.override) == 0
    error_message = "No method-level settings must be created without method_throttling."
  }
}

# EN33-AC3: rejects a throttling rate of 0
run "en33_ac3_rejects_zero_rate_limit" {
  command = plan

  variables {
    throttling_rate_limit = 0
  }

  expect_failures = [var.throttling_rate_limit]
}

# EN33-AC3: rejects a non-integer burst limit
run "en33_ac3_rejects_fractional_burst_limit" {
  command = plan

  variables {
    throttling_burst_limit = 10.5
  }

  expect_failures = [var.throttling_burst_limit]
}

# EN33-AC3: rejects a method path with a leading slash
run "en33_ac3_rejects_method_path_with_leading_slash" {
  command = plan

  variables {
    method_throttling = { "/chat/POST" = { rate_limit = 5, burst_limit = 10 } }
  }

  expect_failures = [var.method_throttling]
}

# EN33-AC3: rejects a method-level limit of 0
run "en33_ac3_rejects_zero_method_limit" {
  command = plan

  variables {
    method_throttling = { "chat/POST" = { rate_limit = 0, burst_limit = 10 } }
  }

  expect_failures = [var.method_throttling]
}

# EN33-AC4: access logs go to a KMS-encrypted group with retention
run "en33_ac4_access_log_group_encrypted_with_retention" {
  command = plan

  variables {
    log_retention_days = 90
  }

  assert {
    condition     = aws_cloudwatch_log_group.access.kms_key_id == var.kms_key_arn
    error_message = "The access log group must be encrypted with the logs KMS key."
  }

  assert {
    condition     = aws_cloudwatch_log_group.access.retention_in_days == 90
    error_message = "The access log group must follow log_retention_days."
  }

  assert {
    condition     = one(aws_api_gateway_stage.this.access_log_settings).destination_arn == aws_cloudwatch_log_group.access.arn
    error_message = "The stage must write its access logs to the access log group."
  }
}

# EN33-AC4: the execution log group is pre-created, encrypted and bounded
run "en33_ac4_execution_log_group_encrypted_with_retention" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.execution.name == "API-Gateway-Execution-Logs_abc123def4/v1"
    error_message = "The execution log group must use the name API Gateway writes to."
  }

  assert {
    condition     = aws_cloudwatch_log_group.execution.kms_key_id == var.kms_key_arn && aws_cloudwatch_log_group.execution.retention_in_days == 14
    error_message = "The execution log group must be KMS-encrypted with retention."
  }
}

# EN33-AC4: the access log format is JSON with technical fields only
run "en33_ac4_access_log_format_json_without_pii" {
  command = plan

  assert {
    condition     = can(jsondecode(one(aws_api_gateway_stage.this.access_log_settings).format))
    error_message = "The access log format must be a JSON document."
  }

  assert {
    condition     = alltrue([for key, value in jsondecode(one(aws_api_gateway_stage.this.access_log_settings).format) : startswith(value, "$context.")])
    error_message = "Every access log field must be a $context variable."
  }

  assert {
    condition = !can(regex(
      "(?i)authorization|header|body|querystring|sourceip|identity|claims",
      join(" ", concat(keys(jsondecode(one(aws_api_gateway_stage.this.access_log_settings).format)), values(jsondecode(one(aws_api_gateway_stage.this.access_log_settings).format))))
    ))
    error_message = "The access log format must not contain the Authorization header, request bodies, headers, query strings, client IPs or identity claims."
  }

  assert {
    condition     = contains(keys(jsondecode(one(aws_api_gateway_stage.this.access_log_settings).format)), "requestId") && contains(keys(jsondecode(one(aws_api_gateway_stage.this.access_log_settings).format)), "status")
    error_message = "The access log must keep the request ID and status for correlation."
  }
}

# EN33-AC4: rejects a KMS alias instead of a key ARN
run "en33_ac4_rejects_kms_alias" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-3:123456789012:alias/sc-dev-logs"
  }

  expect_failures = [var.kms_key_arn]
}

# EN33-AC4: rejects a retention value CloudWatch Logs does not support
run "en33_ac4_rejects_unsupported_retention" {
  command = plan

  variables {
    log_retention_days = 10
  }

  expect_failures = [var.log_retention_days]
}

# EN33-AC5: X-Ray tracing is active on the stage
run "en33_ac5_xray_tracing_enabled" {
  command = plan

  assert {
    condition     = aws_api_gateway_stage.this.xray_tracing_enabled == true
    error_message = "X-Ray tracing must be enabled on the stage."
  }
}

# EN33-AC5: the stage name follows the variable and rejects invalid names
run "en33_ac5_stage_name_follows_variable" {
  command = plan

  variables {
    stage_name = "api"
  }

  assert {
    condition     = aws_api_gateway_stage.this.stage_name == "api" && aws_cloudwatch_log_group.access.name == "/aws/apigateway/sc-dev-api-api-access"
    error_message = "The stage and its access log group must follow stage_name."
  }
}

run "en33_ac5_rejects_invalid_stage_name" {
  command = plan

  variables {
    stage_name = "v1/prod"
  }

  expect_failures = [var.stage_name]
}

# EN33-AC6: one permission per route, scoped to the API, the stage, the method and the path
run "en33_ac6_permissions_scoped_to_method_and_path" {
  command = plan

  assert {
    condition     = length(aws_lambda_permission.invoke) == 4
    error_message = "There must be one invoke permission per route."
  }

  assert {
    condition     = aws_lambda_permission.invoke["tickets|POST /tickets"].source_arn == "arn:aws:execute-api:eu-west-3:123456789012:abc123def4/v1/POST/tickets"
    error_message = "POST /tickets must be limited to its execution ARN."
  }

  assert {
    condition     = aws_lambda_permission.invoke["tickets|GET /tickets/{id}"].source_arn == "arn:aws:execute-api:eu-west-3:123456789012:abc123def4/v1/GET/tickets/*"
    error_message = "Path parameters must become a wildcard segment of the execution ARN."
  }

  assert {
    condition     = aws_lambda_permission.invoke["chat|POST /chat"].source_arn == "arn:aws:execute-api:eu-west-3:123456789012:abc123def4/v1/POST/chat"
    error_message = "POST /chat must be limited to its execution ARN."
  }

  assert {
    condition     = aws_lambda_permission.invoke["kpi|ANY /admin/{proxy+}"].source_arn == "arn:aws:execute-api:eu-west-3:123456789012:abc123def4/v1/*/admin/*"
    error_message = "ANY must become a wildcard method, scoped to the route path."
  }
}

# EN33-AC6: permissions target the alias, the API Gateway principal and this account
run "en33_ac6_permissions_target_alias_and_account" {
  command = plan

  assert {
    condition = alltrue([
      for key, permission in aws_lambda_permission.invoke :
      permission.principal == "apigateway.amazonaws.com" &&
      permission.action == "lambda:InvokeFunction" &&
      permission.qualifier == "live" &&
      permission.source_account == "123456789012"
    ])
    error_message = "Every permission must allow lambda:InvokeFunction on the live alias to API Gateway, from this account only."
  }

  assert {
    condition     = aws_lambda_permission.invoke["chat|POST /chat"].function_name == "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-chat"
    error_message = "A permission must target the function of its integration."
  }

  assert {
    condition     = alltrue([for key, permission in aws_lambda_permission.invoke : permission.source_arn != null && !endswith(permission.source_arn, "/*/*/*")])
    error_message = "No permission may allow every stage, method and path of the API."
  }

  assert {
    condition     = length(distinct([for key, permission in aws_lambda_permission.invoke : permission.statement_id])) == length(aws_lambda_permission.invoke)
    error_message = "Statement IDs must be unique."
  }
}

# EN33-AC6: no permission without integrations
run "en33_ac6_no_permission_without_integrations" {
  command = plan

  variables {
    lambda_integrations = {}
  }

  assert {
    condition     = length(aws_lambda_permission.invoke) == 0
    error_message = "No permission must be created without lambda_integrations."
  }
}

# EN33-AC6: rejects a wildcard in a route
run "en33_ac6_rejects_wildcard_route" {
  command = plan

  variables {
    lambda_integrations = {
      tickets = {
        function_arn = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-tickets"
        routes       = ["GET /tickets/*"]
      }
    }
  }

  expect_failures = [var.lambda_integrations]
}

# EN33-AC6: rejects an integration without route
run "en33_ac6_rejects_integration_without_route" {
  command = plan

  variables {
    lambda_integrations = {
      tickets = {
        function_arn = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-tickets"
        routes       = []
      }
    }
  }

  expect_failures = [var.lambda_integrations]
}

# EN33-AC6: rejects a qualified function ARN (the alias goes in qualifier)
run "en33_ac6_rejects_qualified_function_arn" {
  command = plan

  variables {
    lambda_integrations = {
      tickets = {
        function_arn = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-tickets:live"
        routes       = ["POST /tickets"]
      }
    }
  }

  expect_failures = [var.lambda_integrations]
}

# EN33-AC6: a custom qualifier is passed through
run "en33_ac6_custom_qualifier" {
  command = plan

  variables {
    lambda_integrations = {
      chat = {
        function_arn = "arn:aws:lambda:eu-west-3:123456789012:function:sc-dev-chat"
        qualifier    = "green"
        routes       = ["POST /chat"]
      }
    }
  }

  assert {
    condition     = aws_lambda_permission.invoke["chat|POST /chat"].qualifier == "green"
    error_message = "The permission must follow the integration qualifier."
  }
}

# RF04: the regional web ACL is associated with the stage
run "en33_rf04_web_acl_associated_with_stage" {
  command = plan

  assert {
    condition     = one(aws_wafv2_web_acl_association.this).resource_arn == aws_api_gateway_stage.this.arn
    error_message = "The web ACL must be associated with the stage."
  }

  assert {
    condition     = one(aws_wafv2_web_acl_association.this).web_acl_arn == var.web_acl_arn
    error_message = "The association must use web_acl_arn."
  }
}

# RF04: no association without web ACL
run "en33_rf04_no_association_without_web_acl" {
  command = plan

  variables {
    web_acl_arn = null
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 0
    error_message = "No association must be created without web_acl_arn."
  }
}

# RF04: rejects a CLOUDFRONT-scope web ACL
run "en33_rf04_rejects_cloudfront_web_acl" {
  command = plan

  variables {
    web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/sc-dev-edge/11111111-2222-3333-4444-555555555555"
  }

  expect_failures = [var.web_acl_arn]
}

# EN33-AC1: outputs feed the CloudFront /api/* origin
run "en33_ac1_outputs_for_cloudfront_origin" {
  command = plan

  assert {
    condition     = output.origin_domain_name == "abc123def4.execute-api.eu-west-3.amazonaws.com"
    error_message = "origin_domain_name must be the execute-api domain of the API."
  }

  assert {
    condition     = output.origin_path == "/v1"
    error_message = "origin_path must be the stage path."
  }
}

# EN33-AC1: rejects an invalid name_prefix
run "en33_ac1_rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Bad_Prefix"
  }

  expect_failures = [var.name_prefix]
}

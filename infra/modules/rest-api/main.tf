resource "aws_api_gateway_rest_api" "this" {
  name        = local.name
  description = "Campus incident platform API, generated from the OpenAPI contract."
  body        = local.openapi_body

  # Import errors and warnings from the OpenAPI document fail the apply instead of producing a partial API.
  fail_on_warnings = true

  # Without a custom domain (ADR-0003) the execute-api URL cannot be disabled; the regional web ACL protects it (ADR-0004).
  disable_execute_api_endpoint = false

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(var.tags, { Name = local.name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(local.openapi_body)
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  # checkov:skip=CKV_AWS_120: Response caching is disabled on purpose: responses are per user (tickets, chat) and must never be served from a shared cache.
  # checkov:skip=CKV2_AWS_77: The regional web ACL is owned by the waf module (RF04) and only its ARN is passed in; that ACL includes AWSManagedRulesKnownBadInputsRuleSet, which covers Log4j.
  # checkov:skip=CKV2_AWS_51: Client certificates authenticate API Gateway to HTTP backends; the integrations are Lambda proxy (IAM), so there is no backend to present a certificate to.
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.stage_name
  description   = "Deployment of the OpenAPI contract."

  xray_tracing_enabled  = true
  cache_cluster_enabled = false

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format          = local.access_log_format
  }

  tags = merge(var.tags, { Name = "${local.name}-${var.stage_name}" })

  # The execution log group is pre-created (KMS, retention); otherwise API Gateway creates an unencrypted one that never expires.
  depends_on = [aws_cloudwatch_log_group.execution]
}

# Stage-wide defaults: metrics, error-level execution logs, no data trace (it would write request and response bodies, which hold personal data).
#trivy:ignore:AVD-AWS-0190:Response caching is disabled on purpose: responses are per user behind the Cognito authorizer, a shared cache could leak data across users.
resource "aws_api_gateway_method_settings" "default" {
  # checkov:skip=CKV_AWS_225: Response caching is disabled on purpose: responses are per user and must never be served from a shared cache.
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = true
    logging_level          = "ERROR"
    data_trace_enabled     = false
    caching_enabled        = false
    throttling_rate_limit  = var.throttling_rate_limit
    throttling_burst_limit = var.throttling_burst_limit
  }
}

# Sensitive methods (chat, ticket creation) get their own, stricter limits. The other settings are repeated because a
# method-level entry does not inherit the explicit values of the "*/*" entry.
#trivy:ignore:AVD-AWS-0190:Response caching is disabled on purpose: responses are per user behind the Cognito authorizer, a shared cache could leak data across users.
resource "aws_api_gateway_method_settings" "override" {
  # checkov:skip=CKV_AWS_225: Response caching is disabled on purpose: responses are per user and must never be served from a shared cache.
  for_each = var.method_throttling

  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = each.key

  settings {
    metrics_enabled        = true
    logging_level          = "ERROR"
    data_trace_enabled     = false
    caching_enabled        = false
    throttling_rate_limit  = each.value.rate_limit
    throttling_burst_limit = each.value.burst_limit
  }

  # Method settings of one stage are patched through the same API call; serialise them to avoid ConflictException.
  depends_on = [aws_api_gateway_method_settings.default]
}

# RF04: the regional web ACL applies whichever URL (CloudFront or execute-api) reaches the stage.
resource "aws_wafv2_web_acl_association" "this" {
  count = var.web_acl_arn == null ? 0 : 1

  resource_arn = aws_api_gateway_stage.this.arn
  web_acl_arn  = var.web_acl_arn
}

# The Cognito authorizer is declared in the OpenAPI document (EN-32, ADR-0005). An API without one answers anonymous callers.
check "authorizer_declared" {
  assert {
    condition = (
      anytrue([for _, scheme in try(local.spec.components.securitySchemes, {}) : try(scheme["x-amazon-apigateway-authorizer"] != null, false)]) ||
      anytrue([for _, scheme in try(local.spec.securityDefinitions, {}) : try(scheme["x-amazon-apigateway-authorizer"] != null, false)])
    )
    error_message = "openapi_spec declares no x-amazon-apigateway-authorizer security scheme: every method would be callable without a token."
  }
}

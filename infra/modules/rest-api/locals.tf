data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  name = "${var.name_prefix}-api"

  # One validator for body and parameters, applied at the document root. It is merged into the caller's document so
  # that a request failing its JSON Schema model or its required parameters is rejected with 400 before the Lambda.
  validator_name = "body-and-params"

  spec = jsondecode(var.openapi_spec)

  openapi_body = jsonencode(merge(local.spec, {
    "x-amazon-apigateway-request-validators" = merge(try(local.spec["x-amazon-apigateway-request-validators"], {}), {
      (local.validator_name) = {
        validateRequestBody       = true
        validateRequestParameters = true
      }
    })
    "x-amazon-apigateway-request-validator" = local.validator_name
  }))

  access_log_group_name    = "/aws/apigateway/${local.name}-${var.stage_name}-access"
  execution_log_group_name = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.this.id}/${var.stage_name}"

  # No Authorization header, no body, no query string, no client IP and no identity claim: only technical fields.
  access_log_format = jsonencode({
    requestId          = "$context.requestId"
    extendedRequestId  = "$context.extendedRequestId"
    requestTimeEpoch   = "$context.requestTimeEpoch"
    httpMethod         = "$context.httpMethod"
    resourcePath       = "$context.resourcePath"
    status             = "$context.status"
    protocol           = "$context.protocol"
    responseLength     = "$context.responseLength"
    responseLatency    = "$context.responseLatency"
    integrationStatus  = "$context.integrationStatus"
    integrationLatency = "$context.integrationLatency"
    errorResponseType  = "$context.error.responseType"
    wafResponseCode    = "$context.wafResponseCode"
    xrayTraceId        = "$context.xrayTraceId"
  })

  # One invoke permission per (function, route). API Gateway execution ARN format:
  # <execution arn>/<stage>/<HTTP method>/<resource path>, with "*" for path parameters and for ANY.
  routes = {
    for entry in flatten([
      for key, integration in var.lambda_integrations : [
        for route in integration.routes : {
          key          = "${key}|${route}"
          function_arn = integration.function_arn
          qualifier    = integration.qualifier
          method       = split(" ", route)[0]
          path         = split(" ", route)[1]
        }
      ]
    ]) : entry.key => entry
  }

  route_source_arns = {
    for key, route in local.routes : key => join("/", [
      aws_api_gateway_rest_api.this.execution_arn,
      var.stage_name,
      route.method == "ANY" ? "*" : route.method,
      trimprefix(replace(route.path, "/\\{[^}]*\\}/", "*"), "/"),
    ])
  }
}

# Regional REST API (ADR-0004) generated from an OpenAPI document with a native Cognito authorizer (ADR-0005).
#
# packages/contracts does not exist yet (EN-05): the document is a minimal placeholder rendered from
# openapi/openapi.json.tftpl. When the contract lands, render it here instead, with the same four placeholders
# (user pool ARN and the three alias invoke ARNs); the routes of local.api_routes must follow it.
locals {
  openapi_spec = templatefile("${path.module}/openapi/openapi.json.tftpl", {
    user_pool_arn = module.identity.user_pool_arn
    tickets_uri   = module.tickets.alias_invoke_arn
    kpi_uri       = module.kpi.alias_invoke_arn
    chat_uri      = module.chat.alias_invoke_arn
  })
}

module "rest_api" {
  source = "../../modules/rest-api"

  name_prefix            = var.name_prefix
  openapi_spec           = local.openapi_spec
  stage_name             = var.api_stage_name
  kms_key_arn            = local.kms_key_arns["logs"]
  log_retention_days     = var.log_retention_in_days
  throttling_rate_limit  = var.api_throttling_rate_limit
  throttling_burst_limit = var.api_throttling_burst_limit
  method_throttling      = var.api_method_throttling

  lambda_integrations = {
    tickets = {
      function_arn = module.tickets.function_arn
      routes       = local.api_routes.tickets
    }
    kpi = {
      function_arn = module.kpi.function_arn
      routes       = local.api_routes.kpi
    }
    chat = {
      function_arn = module.chat.function_arn
      routes       = local.api_routes.chat
    }
  }

  # web_acl_arn stays null: the REGIONAL web ACL is associated to the stage by the waf module (waf.tf, RF04).
}

check "api_routes_match_openapi" {
  assert {
    condition = toset(flatten([
      for path, item in jsondecode(local.openapi_spec).paths : [for method in keys(item) : "${upper(method)} ${path}"]
    ])) == toset(flatten(values(local.api_routes)))
    error_message = "The routes of local.api_routes must match the paths and methods of openapi/openapi.json.tftpl, otherwise an invoke permission is missing or useless."
  }
}

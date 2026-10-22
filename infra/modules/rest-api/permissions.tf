# Resource-based policy of each function alias: API Gateway may invoke it only for the route it serves, on this API and
# stage, from this account (confused deputy protection).
resource "aws_lambda_permission" "invoke" {
  for_each = local.routes

  statement_id   = "AllowApiGatewayInvoke-${substr(sha1(each.key), 0, 16)}"
  action         = "lambda:InvokeFunction"
  function_name  = each.value.function_arn
  qualifier      = each.value.qualifier
  principal      = "apigateway.amazonaws.com"
  source_arn     = local.route_source_arns[each.key]
  source_account = data.aws_caller_identity.current.account_id
}

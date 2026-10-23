# Private SPA bucket (OAC) behind CloudFront. /* serves the SPA, /api/* goes to the REST API origin with caching
# disabled and the Authorization header forwarded: same origin, no CORS.
#
# The bucket is encrypted with the edge key of the foundation stack, whose policy already lets cloudfront.amazonaws.com
# use it for the distributions of the account: no second apply of foundation is needed for CloudFront.
#
# Public path contract (ADR-0003): the browser calls https://<distribution>/api/<route>. The /api/* behaviour sends the
# request to the API origin with origin_path "/<stage>", so API Gateway receives /<stage>/api/<route>: the paths of the
# OpenAPI document start with /api (openapi/openapi.json.tftpl). The stage name is shared with the rest-api module.
module "static_site" {
  source = "../../modules/static-site"

  name_prefix             = var.name_prefix
  kms_key_arn             = local.kms_key_arns["edge"]
  content_security_policy = local.content_security_policy
  api_origin_domain_name  = module.rest_api.origin_domain_name
  api_origin_path         = "/${var.api_stage_name}"

  web_acl_id = one(module.waf_cloudfront[*].web_acl_arn)

  # TODO(observability): logging_bucket_name = <log bucket of the observability module>.
}

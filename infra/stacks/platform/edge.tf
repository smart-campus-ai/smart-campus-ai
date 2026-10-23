# Private SPA bucket (OAC) behind CloudFront. /* serves the SPA, /api/* goes to the REST API origin with caching
# disabled and the Authorization header forwarded: same origin, no CORS.
#
# The KMS key policy of the data key must let cloudfront.amazonaws.com use the key for this distribution (the
# distribution_arn output is published for that); see the README of the stack.
module "static_site" {
  source = "../../modules/static-site"

  name_prefix             = var.name_prefix
  kms_key_arn             = local.kms_key_arns["data"]
  content_security_policy = local.content_security_policy
  api_origin_domain_name  = module.rest_api.origin_domain_name
  api_origin_path         = module.rest_api.origin_path

  # TODO(waf): web_acl_id = <ARN of the CLOUDFRONT-scope web ACL of the waf module, PR #106>.
  # TODO(observability): logging_bucket_name = <log bucket of the observability module>.
}

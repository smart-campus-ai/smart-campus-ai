# Values the application pipeline (front, back, tests) needs, published under /smartcampus/<env>/platform/<key> as plain
# String parameters (EN-05). No secret: identifiers, names and public URLs only. A plain String is also what the
# read-only plan role can refresh.
locals {
  published_parameters = merge(
    {
      "api/invoke_url"              = module.rest_api.invoke_url
      "site/url"                    = module.static_site.site_url
      "site/bucket_name"            = module.static_site.bucket_name
      "site/distribution_id"        = module.static_site.distribution_id
      "identity/user_pool_id"       = module.identity.user_pool_id
      "identity/client_id"          = module.identity.client_id
      "identity/hosted_ui_base_url" = module.identity.hosted_ui_base_url
    },
    { for name, function_name in local.lambda_function_names : "lambda/${name}/name" => function_name },
    # Read by the second apply of the foundation stack (data key policy), docs/runbooks/foundation-second-apply.md.
    var.enable_malware_protection ? {
      "attachments/malware-role-arn" = module.attachments_bucket.malware_protection_role_arn
    } : {},
    var.enable_knowledge_base ? {
      "kb/knowledge_base_id"  = module.knowledge_base[0].knowledge_base_id
      "kb/data_source_id"     = module.knowledge_base[0].data_source_id
      "kb/source_bucket_name" = module.knowledge_base[0].source_bucket_name
    } : {},
  )
}

resource "aws_ssm_parameter" "published" {
  # checkov:skip=CKV2_AWS_34: Not a secret (identifiers, names and public URLs). A SecureString would need kms:Decrypt, which the read-only plan role is denied, so the stack could no longer be planned in pull requests.
  for_each = local.published_parameters

  name        = "${local.platform_ssm_prefix}/${each.key}"
  description = "Published by the platform stack for the application pipeline and the tests."
  type        = "String"
  value       = each.value
}

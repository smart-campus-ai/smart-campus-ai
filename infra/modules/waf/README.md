# waf

Web ACL AWS WAFv2 réutilisable pour les deux scopes de RF04 : `CLOUDFRONT` (le caller passe un provider us-east-1 : `providers = { aws = aws.us_east_1 }`) et `REGIONAL` (stage de l'API REST).

- Groupes gérés toujours actifs : Common, KnownBadInputs, IpReputation, AnonymousIp, SQLi ; Bot Control en option (`enable_bot_control`). Plus une limite de taille du corps.
- Limitation de débit par IP et, en option, par en-tête `Authorization` ; réponse 429 avec `Retry-After`.
- Journaux dans le groupe CloudWatch `aws-waf-logs-<prefix>-<scope>`, chiffré par la clé KMS `logs`, en-têtes `authorization` et `cookie` masqués.
- Aucune association pour CloudFront (utiliser `web_acl_id` de la distribution) ; `associated_resource_arns` n'accepte que des ARN de stage d'API REST (`arn:<partition>:apigateway:<region>::/restapis/<id>/stages/<stage>`).

## Périmètre : module, câblage de la stack et preuves d'exécution

Ce module ne livre que la web ACL. Le câblage et les preuves d'exécution relèvent d'autres livrables.

| AC | Preuve dans le module (`tests/unit.tftest.hcl`) | Livrable hors module |
| -- | ----------------------------------------------- | -------------------- |
| AC1 | `rf04_ac1_*` : ACL CLOUDFRONT, groupes gérés, limite de taille | `infra/stacks/platform` : instancier le module avec `providers = { aws = aws.us_east_1 }` et passer `web_acl_arn` au `web_acl_id` de la distribution |
| AC2 | `rf04_ac2_*` : ACL REGIONAL, mêmes groupes | `infra/stacks/platform` : instancier le module REGIONAL et passer `{ api = <ARN du stage> }` à `associated_resource_arns` |
| AC5 | `rf04_ac5_*` : règles de débit sur l'ACL régionale associée | même câblage que AC2, preuve d'exécution sur l'URL `execute-api` directe dans `tests/smoke` (Hurl) |
| AC3, AC4 | `rf04_ac3_*`, `rf04_ac4_*` : forme du plan seulement | `tests/smoke` (Hurl : 429 et `Retry-After`) et `tests/perf` (k6 : seuils par IP et par utilisateur), EN-83 |
| AC6 | `rf04_ac6_*` : forme du plan seulement | `tests/smoke` (Hurl : 403 sur requête malveillante et corps trop gros), EN-83 |

Les tests unitaires du module ne prouvent donc pas les AC3 à AC6 à l'exécution : ces preuves exigent un environnement déployé (`task smoke ENV=dev`, `task perf ENV=dev`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.13.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.70.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.waf](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_resource_policy.waf](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_resource_policy) | resource |
| [aws_wafv2_ip_set.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_ip_set) | resource |
| [aws_wafv2_web_acl.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl) | resource |
| [aws_wafv2_web_acl_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association) | resource |
| [aws_wafv2_web_acl_logging_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_logging_configuration) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.log_delivery](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_ip_addresses"></a> [allowed\_ip\_addresses](#input\_allowed\_ip\_addresses) | IPv4 and IPv6 CIDR blocks that skip the rate-based rules only (they are labelled, not allowed): the body size limit and the managed groups (SQLi, KnownBadInputs...) still apply. Meant for a trusted load-test source; keep it empty in prod (the module has no environment variable to enforce it, the stack tfvars of prod must leave it empty). Prefix length 0 is refused by AWS WAF. | `list(string)` | `[]` | no |
| <a name="input_associated_resource_arns"></a> [associated\_resource\_arns](#input\_associated\_resource\_arns) | ARNs of the regional resources (API Gateway REST stages) to associate with the web ACL, keyed by a static name of your choice (for example { api = aws\_api\_gateway\_stage.this.arn }). Static keys keep an association from being recreated when the map changes. REGIONAL scope only: a CloudFront distribution references the ACL through its web\_acl\_id. | `map(string)` | `{}` | no |
| <a name="input_blocked_ip_addresses"></a> [blocked\_ip\_addresses](#input\_blocked\_ip\_addresses) | IPv4 and IPv6 CIDR blocks that are always blocked. Evaluated before allowed\_ip\_addresses, so a deny wins. Prefix length 0 is refused by AWS WAF. | `list(string)` | `[]` | no |
| <a name="input_enable_bot_control"></a> [enable\_bot\_control](#input\_enable\_bot\_control) | Add the AWSManagedRulesBotControlRuleSet group (COMMON inspection level). Billed per request on top of the web ACL, hence off by default. | `bool` | `false` | no |
| <a name="input_enable_log_resource_policy"></a> [enable\_log\_resource\_policy](#input\_enable\_log\_resource\_policy) | Create the CloudWatch Logs resource policy that lets AWS WAF deliver to the log group, restricted to the logs ARNs of this account and region (aws:SourceArn, as documented for WAF log delivery) and to this account (aws:SourceAccount). Disable it only if the policy is managed elsewhere: an account holds at most 10 such policies per region. | `bool` | `true` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the customer-managed KMS key ("logs" key, EN-14) that encrypts the WAF log group. It must live in the same region as the log group (us-east-1 for CLOUDFRONT) and its key policy must allow the CloudWatch Logs service principal of that region. | `string` | n/a | yes |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention of the WAF log group, in days (dev 14, prod 90). | `number` | n/a | yes |
| <a name="input_max_body_size_bytes"></a> [max\_body\_size\_bytes](#input\_max\_body\_size\_bytes) | Requests with a body larger than this are blocked. Capped at 8192 bytes; the default inspection size of AWS WAF is 16 KB on CloudFront and API Gateway, and the 8 KB block is also covered by the SizeRestrictions\_BODY rule of the Common group. | `number` | `8192` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, for example "sc-dev". The web ACL is named <prefix>-waf-<scope> and the log group aws-waf-logs-<prefix>-<scope>. | `string` | n/a | yes |
| <a name="input_rate_limit_path_prefix"></a> [rate\_limit\_path\_prefix](#input\_rate\_limit\_path\_prefix) | Restrict the per-user rule (rate\_limit\_per\_authorization) to requests whose URI path starts with this prefix (for example "/api/chat" to protect inference). The per-IP rule is never filtered. null applies the per-user rule to every request. Lowercase, matched case-insensitively. On the REGIONAL ACL, a request sent straight to the execute-api URL may carry the stage name first ("/<stage>/api/chat"), so check the prefix against that URL too. | `string` | `null` | no |
| <a name="input_rate_limit_per_authorization"></a> [rate\_limit\_per\_authorization](#input\_rate\_limit\_per\_authorization) | Maximum number of requests carrying the same Authorization header (per user) over rate\_limit\_window\_seconds before further requests are blocked with a 429. null disables the per-user rule. Meant for the REGIONAL ACL of the API. | `number` | `null` | no |
| <a name="input_rate_limit_per_ip"></a> [rate\_limit\_per\_ip](#input\_rate\_limit\_per\_ip) | Maximum number of requests from one source IP over rate\_limit\_window\_seconds before further requests are blocked with a 429. AWS WAF does not accept a limit below 10. | `number` | n/a | yes |
| <a name="input_rate_limit_window_seconds"></a> [rate\_limit\_window\_seconds](#input\_rate\_limit\_window\_seconds) | Evaluation window of the rate-based rules, in seconds. Also returned to throttled clients in the Retry-After header. | `number` | `300` | no |
| <a name="input_scope"></a> [scope](#input\_scope) | Scope of the web ACL: CLOUDFRONT (the caller must pass a us-east-1 provider as "aws") or REGIONAL (API Gateway REST stage, in the region of the provider). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ip_set_arns"></a> [ip\_set\_arns](#output\_ip\_set\_arns) | ARNs of the IP sets, keyed by allow-ipv4, allow-ipv6, block-ipv4 and block-ipv6 (only the sets that have addresses). |
| <a name="output_log_group_arn"></a> [log\_group\_arn](#output\_log\_group\_arn) | ARN of the WAF log group. |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | Name of the WAF log group (aws-waf-logs-<prefix>-<scope>). |
| <a name="output_web_acl_arn"></a> [web\_acl\_arn](#output\_web\_acl\_arn) | ARN of the web ACL. Pass it to the CloudFront distribution web\_acl\_id for the CLOUDFRONT scope. |
| <a name="output_web_acl_id"></a> [web\_acl\_id](#output\_web\_acl\_id) | ID of the web ACL. |
| <a name="output_web_acl_name"></a> [web\_acl\_name](#output\_web\_acl\_name) | Name of the web ACL (<prefix>-waf-<scope>), used by the WAF block alarms. |
<!-- END_TF_DOCS -->

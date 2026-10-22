# rest-api

API Gateway REST régionale (ADR-0004) générée depuis un document OpenAPI : validation des requêtes (corps et paramètres), stage avec logs d'accès JSON chiffrés (clé `logs`), tracing X-Ray, throttling par stage et par méthode, association optionnelle d'une web ACL WAF régionale (RF04) et permissions d'invocation Lambda limitées à chaque route.

L'authorizer Cognito (EN-32, ADR-0005) est déclaré dans le document OpenAPI. Le rôle CloudWatch des paramètres de compte API Gateway est hors module (niveau compte).

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
| [aws_api_gateway_deployment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_deployment) | resource |
| [aws_api_gateway_method_settings.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method_settings) | resource |
| [aws_api_gateway_method_settings.override](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method_settings) | resource |
| [aws_api_gateway_rest_api.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_rest_api) | resource |
| [aws_api_gateway_stage.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_stage) | resource |
| [aws_cloudwatch_log_group.access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_group.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_lambda_permission.invoke](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_wafv2_web_acl_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the "logs" KMS key (EN-14) that encrypts the access and execution log groups. Its key policy must allow the CloudWatch Logs service principal of the region. | `string` | n/a | yes |
| <a name="input_lambda_integrations"></a> [lambda\_integrations](#input\_lambda\_integrations) | Lambda functions invoked by the API, keyed by a stable name (for example "tickets"). function\_arn is the unqualified function ARN, qualifier the alias targeted by the integration URIs ("live"), routes the "<HTTP method> <path>" pairs of the OpenAPI document served by the function (path parameters allowed, ANY for every method). One invoke permission is created per route, limited to that stage, method and path. | <pre>map(object({<br/>    function_arn = string<br/>    qualifier    = optional(string, "live")<br/>    routes       = list(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention, in days, of the access and execution log groups (dev 14, prod 90). Must be a value accepted by CloudWatch Logs. | `number` | n/a | yes |
| <a name="input_method_throttling"></a> [method\_throttling](#input\_method\_throttling) | Stricter throttling for sensitive methods (chat, ticket creation), keyed by method path "<resource path without leading slash>/<HTTP method>", for example "chat/POST" or "tickets/POST". | <pre>map(object({<br/>    rate_limit  = number<br/>    burst_limit = number<br/>  }))</pre> | `{}` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, for example "sc-dev". Resources are named "<name\_prefix>-api". | `string` | n/a | yes |
| <a name="input_openapi_spec"></a> [openapi\_spec](#input\_openapi\_spec) | OpenAPI 3 (or Swagger 2) document of the API as a JSON string, rendered by the caller from packages/contracts (the caller injects the Lambda invocation URIs, which point to the "live" alias). Every operation must use an aws\_proxy integration. The Cognito authorizer (EN-32) is declared in the document itself (components.securitySchemes with x-amazon-apigateway-authorizer). The module adds the body and parameter request validator at the document root. | `string` | n/a | yes |
| <a name="input_stage_name"></a> [stage\_name](#input\_stage\_name) | Name of the API stage. It is the path prefix of the invoke URL and the origin path of the CloudFront /api/* behaviour. | `string` | `"v1"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_throttling_burst_limit"></a> [throttling\_burst\_limit](#input\_throttling\_burst\_limit) | Burst capacity, in requests, applied to every method of the stage. | `number` | n/a | yes |
| <a name="input_throttling_rate_limit"></a> [throttling\_rate\_limit](#input\_throttling\_rate\_limit) | Steady-state request rate, in requests per second, applied to every method of the stage. | `number` | n/a | yes |
| <a name="input_web_acl_arn"></a> [web\_acl\_arn](#input\_web\_acl\_arn) | ARN of the REGIONAL WAF web ACL associated with the stage (RF04, ADR-0004). Null leaves the stage without a web ACL; the platform stack always sets it. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_log_group_arn"></a> [access\_log\_group\_arn](#output\_access\_log\_group\_arn) | ARN of the access log group. |
| <a name="output_access_log_group_name"></a> [access\_log\_group\_name](#output\_access\_log\_group\_name) | Name of the access log group. |
| <a name="output_execution_arn"></a> [execution\_arn](#output\_execution\_arn) | Execution ARN of the REST API (prefix of the aws:SourceArn values of the invoke permissions). |
| <a name="output_execution_log_group_name"></a> [execution\_log\_group\_name](#output\_execution\_log\_group\_name) | Name of the execution log group. |
| <a name="output_invoke_url"></a> [invoke\_url](#output\_invoke\_url) | Invoke URL of the stage (https://<id>.execute-api.<region>.amazonaws.com/<stage>). |
| <a name="output_origin_domain_name"></a> [origin\_domain\_name](#output\_origin\_domain\_name) | Domain name of the API, used as the domain\_name of the CloudFront /api/* origin (EN-21). |
| <a name="output_origin_path"></a> [origin\_path](#output\_origin\_path) | Path prefix of the stage, used as the origin\_path of the CloudFront /api/* origin (EN-21). |
| <a name="output_rest_api_arn"></a> [rest\_api\_arn](#output\_rest\_api\_arn) | ARN of the REST API. |
| <a name="output_rest_api_id"></a> [rest\_api\_id](#output\_rest\_api\_id) | ID of the REST API. |
| <a name="output_stage_arn"></a> [stage\_arn](#output\_stage\_arn) | ARN of the stage (resource of the WAF association). |
| <a name="output_stage_name"></a> [stage\_name](#output\_stage\_name) | Name of the stage. |
<!-- END_TF_DOCS -->

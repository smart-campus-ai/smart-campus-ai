# lambda-service

Module générique d'une fonction Lambda (EN-41) : arm64, tracing X-Ray actif, logs JSON dans un log group explicite chiffré par KMS, rôle d'exécution dédié avec permissions boundary, alias `live` exposé aux intégrations, DLQ SQS chiffrée et destination d'échec optionnelles.

L'infrastructure possède la configuration, le pipeline applicatif (EN-74) possède le code : le premier apply déploie une archive de remplacement, puis `filename`, `source_code_hash`, `s3_key` et `s3_object_version` sont ignorés. Les intégrations (API Gateway, event source mappings, Scheduler) ciblent `alias_arn`, jamais `$LATEST`.

Les clés KMS (logs, DLQ, variables d'environnement) et la permissions boundary sont des entrées (EN-14, EN-13). La clé de logs doit autoriser le service CloudWatch Logs dans sa key policy. Aucun secret en variable d'environnement : passer le nom d'un paramètre SSM (clé suffixée `_SSM_PARAMETER`) et le lire à l'exécution.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.13.0 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | ~> 2.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_archive"></a> [archive](#provider\_archive) | 2.8.1 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.70.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_lambda_alias.live](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_alias) | resource |
| [aws_lambda_function.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_function_event_invoke_config.live](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function_event_invoke_config) | resource |
| [aws_sqs_queue.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_policy.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [archive_file.placeholder](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_description"></a> [description](#input\_description) | Description of the function. | `string` | `null` | no |
| <a name="input_dlq_kms_key_arn"></a> [dlq\_kms\_key\_arn](#input\_dlq\_kms\_key\_arn) | ARN of the customer-managed KMS key that encrypts the dead-letter queue. Required when enable\_dlq is true. The execution role is granted kms:GenerateDataKey and kms:Decrypt on it. | `string` | `null` | no |
| <a name="input_dlq_message_retention_seconds"></a> [dlq\_message\_retention\_seconds](#input\_dlq\_message\_retention\_seconds) | Retention of the messages of the dead-letter queue, in seconds (maximum 14 days). | `number` | `1209600` | no |
| <a name="input_enable_dlq"></a> [enable\_dlq](#input\_enable\_dlq) | Create an SQS dead-letter queue (encrypted with dlq\_kms\_key\_arn) that receives the failed asynchronous invocations. | `bool` | `false` | no |
| <a name="input_environment_kms_key_arn"></a> [environment\_kms\_key\_arn](#input\_environment\_kms\_key\_arn) | ARN of the customer-managed KMS key (domain data) that encrypts the environment variables. Required: the AWS-managed key is not accepted. The execution role is granted kms:Decrypt on it, only for this function. | `string` | n/a | yes |
| <a name="input_environment_variables"></a> [environment\_variables](#input\_environment\_variables) | Plain environment variables of the function. Never put a secret here: pass the name of the SSM parameter or Secrets Manager secret (key suffixed with \_SSM\_PARAMETER or \_SECRET\_ARN) and read it at runtime. | `map(string)` | `{}` | no |
| <a name="input_extra_policy_json"></a> [extra\_policy\_json](#input\_extra\_policy\_json) | Additional IAM policy document (JSON) merged into the execution role policy: the data access of the function (tables, buckets, parameters, keys). Refused: NotAction and NotResource, Allow statements with Resource "*", with a wildcard service ("*", "*:*"), with iam:*, sts:*, kms:*, iam:PassRole, lambda:Update*, or with lambda wildcards on functions (lambda:*, lambda:*Function*). Scope every resource. | `string` | `null` | no |
| <a name="input_function_name"></a> [function\_name](#input\_function\_name) | Short name of the function (for example "tickets"). The deployed function is named <name\_prefix>-<function\_name>. | `string` | n/a | yes |
| <a name="input_handler"></a> [handler](#input\_handler) | Function entrypoint in the deployed code (for example "app.handler"). Chosen by the application team. | `string` | n/a | yes |
| <a name="input_log_retention_in_days"></a> [log\_retention\_in\_days](#input\_log\_retention\_in\_days) | Retention of the function log group, in days (dev 14, prod 90). A retention of 0 (never expire) is refused. | `number` | n/a | yes |
| <a name="input_logs_kms_key_arn"></a> [logs\_kms\_key\_arn](#input\_logs\_kms\_key\_arn) | ARN of the customer-managed KMS key (domain logs) that encrypts the log group. Its key policy must allow the CloudWatch Logs service. | `string` | n/a | yes |
| <a name="input_memory_size"></a> [memory\_size](#input\_memory\_size) | Memory of the function, in MB. | `number` | `256` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, in the form sc-<env> (for example "sc-dev"). | `string` | n/a | yes |
| <a name="input_on_failure_destination_arn"></a> [on\_failure\_destination\_arn](#input\_on\_failure\_destination\_arn) | ARN of an SQS queue, SNS topic, EventBridge bus or Lambda function that receives the failed asynchronous invocations of the live alias. The execution role is granted the matching send action; if the destination is encrypted with a customer-managed key, grant that key through extra\_policy\_json. | `string` | `null` | no |
| <a name="input_permissions_boundary_arn"></a> [permissions\_boundary\_arn](#input\_permissions\_boundary\_arn) | ARN of the project permissions boundary (EN-13) attached to the execution role. The policy name must contain name\_prefix, so a dev function cannot use the prod boundary (per-environment boundaries, single account). null attaches no boundary: only for the workshop exception of ADR-0014 (stacks enforce its scope and expiry). | `string` | n/a | yes |
| <a name="input_reserved_concurrent_executions"></a> [reserved\_concurrent\_executions](#input\_reserved\_concurrent\_executions) | Reserved concurrency of the function. -1 leaves the function unreserved; 0 throttles every invocation. Reserving concurrency is only possible while the account keeps at least 10 unreserved executions. | `number` | `-1` | no |
| <a name="input_runtime"></a> [runtime](#input\_runtime) | Lambda runtime identifier (for example "python3.13" or "nodejs24.x"). Chosen by the application team. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_timeout"></a> [timeout](#input\_timeout) | Timeout of the function, in seconds. | `number` | `10` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alias_arn"></a> [alias\_arn](#output\_alias\_arn) | ARN of the live alias, to use for every integration (API Gateway, event source mapping, Scheduler target, permissions). |
| <a name="output_alias_invoke_arn"></a> [alias\_invoke\_arn](#output\_alias\_invoke\_arn) | Invoke ARN of the live alias (API Gateway integration URI). |
| <a name="output_alias_name"></a> [alias\_name](#output\_alias\_name) | Name of the live alias. |
| <a name="output_dlq_arn"></a> [dlq\_arn](#output\_dlq\_arn) | ARN of the dead-letter queue, or null when enable\_dlq is false (alarm on its depth). |
| <a name="output_dlq_name"></a> [dlq\_name](#output\_dlq\_name) | Name of the dead-letter queue, or null when enable\_dlq is false (CloudWatch metric dimension). |
| <a name="output_function_arn"></a> [function\_arn](#output\_function\_arn) | ARN of the function (unqualified). Integrations must use alias\_arn. |
| <a name="output_function_name"></a> [function\_name](#output\_function\_name) | Name of the function. |
| <a name="output_log_group_arn"></a> [log\_group\_arn](#output\_log\_group\_arn) | ARN of the function log group. |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | Name of the function log group. |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the execution role. |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | Name of the execution role. |
<!-- END_TF_DOCS -->

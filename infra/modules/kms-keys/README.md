# kms-keys

Une clé KMS gérée par le client par domaine (`data`, `logs`, `ai` par défaut), avec rotation automatique, alias `alias/<préfixe>-<domaine>` et politique de clé explicite : délégation à IAM via `:root`, administrateurs nommés, aucun principal `*`.

Les droits des services AWS (CloudWatch Logs, CloudTrail, Config, CloudFront OAC, GuardDuty Malware Protection, Bedrock, usage via DynamoDB / SQS / S3) sont désactivés par défaut et activés par des entrées, chacun avec ses conditions (contexte de chiffrement, `aws:SourceArn`, `aws:SourceAccount`, `kms:ViaService`, `kms:CallerAccount`). Une règle EventBridge optionnelle alerte (SNS) sur `ScheduleKeyDeletion` et `DisableKey`.

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
| [aws_cloudwatch_event_rule.key_protection](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.key_protection](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_admin_principal_arns"></a> [admin\_principal\_arns](#input\_admin\_principal\_arns) | IAM role or user ARNs that administer the keys (including ScheduleKeyDeletion, DisableKey, PutKeyPolicy). Use the bootstrap human and a break-glass role, never a CI role. The principals must exist, and must include whoever runs the apply that creates the keys. | `list(string)` | n/a | yes |
| <a name="input_ai_via_services"></a> [ai\_via\_services](#input\_ai\_via\_services) | Services through which principals of the account may use the ai key (kms:ViaService + kms:CallerAccount). Empty disables the statement. | `list(string)` | `[]` | no |
| <a name="input_alert_topic_arn"></a> [alert\_topic\_arn](#input\_alert\_topic\_arn) | ARN of the SNS topic that receives the key deletion alerts. Required when enable\_deletion\_alerts is true. Its policy must allow events.amazonaws.com to publish (use the deletion\_alert\_rule\_arn output as aws:SourceArn). | `string` | `null` | no |
| <a name="input_cloudfront_distribution_arns"></a> [cloudfront\_distribution\_arns](#input\_cloudfront\_distribution\_arns) | CloudFront distribution ARNs allowed to decrypt objects of SSE-KMS buckets through their origin access control (aws:SourceArn). Empty disables the statement. | `list(string)` | `[]` | no |
| <a name="input_data_via_services"></a> [data\_via\_services](#input\_data\_via\_services) | Services through which principals of the account may use the data key (kms:ViaService + kms:CallerAccount). Empty disables the statement. | `list(string)` | `[]` | no |
| <a name="input_enable_bedrock"></a> [enable\_bedrock](#input\_enable\_bedrock) | Let Amazon Bedrock use the ai key for the Knowledge Bases of this account (aws:SourceAccount + aws:SourceArn). | `bool` | `false` | no |
| <a name="input_enable_cloudtrail"></a> [enable\_cloudtrail](#input\_enable\_cloudtrail) | Let CloudTrail use the logs key to encrypt trail log files (GenerateDataKey, restricted to trails of this account). | `bool` | `false` | no |
| <a name="input_enable_cloudwatch_logs"></a> [enable\_cloudwatch\_logs](#input\_enable\_cloudwatch\_logs) | Let CloudWatch Logs use the logs key for log groups, only when the log group ARN matches the name patterns (encryption context). | `bool` | `false` | no |
| <a name="input_enable_config"></a> [enable\_config](#input\_enable\_config) | Let the AWS Config service-linked role use the logs key to deliver to S3. The service-linked role must already exist, otherwise the key policy is rejected. | `bool` | `false` | no |
| <a name="input_enable_deletion_alerts"></a> [enable\_deletion\_alerts](#input\_enable\_deletion\_alerts) | Create an EventBridge rule that publishes to alert\_topic\_arn when ScheduleKeyDeletion or DisableKey is called on one of these keys. Needs CloudTrail management events (security baseline). | `bool` | `false` | no |
| <a name="input_enable_log_delivery"></a> [enable\_log\_delivery](#input\_enable\_log\_delivery) | Let the vended logs delivery service (delivery.logs.amazonaws.com, used by WAF and API Gateway logs sent to S3) use the logs key, restricted to delivery sources of this account. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name, applied as the Environment tag on every key (the CI apply roles require it on kms:CreateKey). | `string` | n/a | yes |
| <a name="input_guardduty_malware_protection_role_arns"></a> [guardduty\_malware\_protection\_role\_arns](#input\_guardduty\_malware\_protection\_role\_arns) | ARNs of the IAM roles used by GuardDuty Malware Protection for S3 to scan and tag objects of SSE-KMS buckets. The roles must exist. Empty disables the statement. | `list(string)` | `[]` | no |
| <a name="input_keys"></a> [keys](#input\_keys) | Customer managed keys to create, one per domain, keyed by domain name. The alias is alias/<name\_prefix>-<domain>. The service grants below target the domains "logs", "data" and "ai" and need the matching key to exist. | <pre>map(object({<br/>    description = string<br/>  }))</pre> | <pre>{<br/>  "ai": {<br/>    "description": "Encrypts the AI assistant data: Bedrock Knowledge Base sources and ingestion"<br/>  },<br/>  "data": {<br/>    "description": "Encrypts application data at rest: DynamoDB tables, SQS queues, S3 buckets"<br/>  },<br/>  "logs": {<br/>    "description": "Encrypts logs: CloudWatch Logs log groups, CloudTrail, AWS Config"<br/>  }<br/>}</pre> | no |
| <a name="input_kms_deletion_window_in_days"></a> [kms\_deletion\_window\_in\_days](#input\_kms\_deletion\_window\_in\_days) | Waiting period, in days, before a key is deleted after a deletion request. Use a long value in prod. | `number` | n/a | yes |
| <a name="input_log_group_name_patterns"></a> [log\_group\_name\_patterns](#input\_log\_group\_name\_patterns) | Log group name patterns, in addition to "<name\_prefix>-*", that CloudWatch Logs may encrypt with the logs key (for example "/aws/lambda/sc-dev-*"). Each pattern needs at least 3 literal characters and may end with "*". | `list(string)` | `[]` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name and alias, <project>-<env> (for example "sc-dev"). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alias_arns"></a> [alias\_arns](#output\_alias\_arns) | ARN of the alias of each key, by domain. |
| <a name="output_alias_names"></a> [alias\_names](#output\_alias\_names) | Alias of each key, by domain (alias/<name\_prefix>-<domain>). |
| <a name="output_deletion_alert_rule_arn"></a> [deletion\_alert\_rule\_arn](#output\_deletion\_alert\_rule\_arn) | ARN of the key deletion alert EventBridge rule, or null when alerts are disabled. Use it as aws:SourceArn in the alert topic policy. |
| <a name="output_key_arns"></a> [key\_arns](#output\_key\_arns) | ARN of each key, by domain. Published to SSM by the foundation stack (EN-14 AC4). |
| <a name="output_key_ids"></a> [key\_ids](#output\_key\_ids) | ID of each key, by domain. |
<!-- END_TF_DOCS -->

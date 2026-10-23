# kms-keys

Une clé KMS gérée par le client par domaine (`data`, `logs`, `ai` par défaut), avec rotation automatique, alias `alias/<préfixe>-<domaine>` et politique de clé explicite : délégation à IAM via `:root`, administrateurs nommés, aucun principal `*`.

Les droits des services AWS (CloudWatch Logs, CloudTrail, Config, CloudFront OAC, GuardDuty Malware Protection, Bedrock, usage via DynamoDB / SQS / S3) sont désactivés par défaut et activés par des entrées, chacun avec ses conditions (contexte de chiffrement, `aws:SourceArn`, `aws:SourceAccount`, `kms:ViaService`, `kms:CallerAccount`). Une règle EventBridge optionnelle alerte (SNS) sur `ScheduleKeyDeletion`, `DisableKey`, `DisableKeyRotation` et `PutKeyPolicy` (clé), et sur `DeleteAlias` (alias).

## Choix de sécurité

- **Usage délégué à IAM.** `EnableIamDelegation` donne à `:root` les actions d'usage (`Encrypt`, `Decrypt`, `ReEncrypt*`, `GenerateDataKey*`, `DescribeKey`) et de lecture (`GetKeyPolicy`, `GetKeyRotationStatus`, `ListResourceTags`) : un principal du compte n'agit que si sa politique IAM l'y autorise. Les rôles plan et apply de la CI lisent donc les clés par IAM. Il n'y a pas d'instruction `kms:ViaService` en plus : elle serait redondante, la politique IAM du rôle est le contrôle de moindre privilège. `TagResource` et l'administration restent aux `admin_principal_arns`.
- **`kms:PutKeyPolicy` pour `:root`** (consigne AWS contre le verrouillage). Tout principal IAM qui reçoit `kms:PutKeyPolicy` peut donc réécrire la politique : ne jamais l'accorder hors administrateurs, et traiter l'alerte `PutKeyPolicy` comme un incident (`enable_deletion_alerts`).
- **Compte partagé entre environnements.** Les ARN de trails CloudTrail et de delivery sources sont limités à `<name_prefix>-*` et les motifs de `log_group_name_patterns` doivent contenir `<name_prefix>-`. Un ARN de base de connaissances Bedrock porte un identifiant généré, il ne peut pas être borné par le préfixe : la clé `ai` est propre à l'environnement et la clé n'est accordée qu'aux bases du compte.
- **Fenêtre de suppression.** En `prod`, `kms_deletion_window_in_days` doit valoir 30 (précondition sur les clés).

## Publication SSM (EN-14 AC4)

Le module ne crée aucun paramètre SSM : la stack `foundation` compose les sorties `key_arns` (et `alias_names`) et publie, sous `/smartcampus/<env>/foundation/` :

| Paramètre | Valeur |
| --------- | ------ |
| `kms_data_key_arn` | `key_arns["data"]` |
| `kms_logs_key_arn` | `key_arns["logs"]` |
| `kms_ai_key_arn` | `key_arns["ai"]` |

La stack `platform` lit ces paramètres, sans `terraform_remote_state`.

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
| <a name="input_admin_principal_arns"></a> [admin\_principal\_arns](#input\_admin\_principal\_arns) | IAM role or user ARNs that administer the keys (including ScheduleKeyDeletion, DisableKey, PutKeyPolicy). Use the bootstrap human and a break-glass role, never a CI role (CI roles read the keys through IAM, with the read-only actions delegated to the account root). The principals must exist, and must include whoever runs the apply that creates the keys. | `list(string)` | n/a | yes |
| <a name="input_alert_topic_arn"></a> [alert\_topic\_arn](#input\_alert\_topic\_arn) | ARN of the SNS topic that receives the key deletion alerts. Required when enable\_deletion\_alerts is true. Its policy must allow events.amazonaws.com to publish (use the deletion\_alert\_rule\_arn output as aws:SourceArn). | `string` | `null` | no |
| <a name="input_cloudfront_distribution_arns"></a> [cloudfront\_distribution\_arns](#input\_cloudfront\_distribution\_arns) | CloudFront distribution ARNs allowed to decrypt objects of SSE-KMS buckets through their origin access control (aws:SourceArn). Empty disables the statement. | `list(string)` | `[]` | no |
| <a name="input_enable_bedrock"></a> [enable\_bedrock](#input\_enable\_bedrock) | Let Amazon Bedrock use the ai key for the Knowledge Bases of this account (aws:SourceAccount + aws:SourceArn). | `bool` | `false` | no |
| <a name="input_enable_cloudtrail"></a> [enable\_cloudtrail](#input\_enable\_cloudtrail) | Let CloudTrail use the logs key to encrypt trail log files (GenerateDataKey, restricted to trails of this account). | `bool` | `false` | no |
| <a name="input_enable_cloudwatch_logs"></a> [enable\_cloudwatch\_logs](#input\_enable\_cloudwatch\_logs) | Let CloudWatch Logs use the logs key for log groups, only when the log group ARN matches the name patterns (encryption context). | `bool` | `false` | no |
| <a name="input_enable_config"></a> [enable\_config](#input\_enable\_config) | Let the AWS Config service-linked role use the logs key to deliver to S3. The service-linked role must already exist, otherwise the key policy is rejected. | `bool` | `false` | no |
| <a name="input_enable_deletion_alerts"></a> [enable\_deletion\_alerts](#input\_enable\_deletion\_alerts) | Create an EventBridge rule that publishes to alert\_topic\_arn when ScheduleKeyDeletion, DisableKey, DisableKeyRotation or PutKeyPolicy is called on one of these keys, or DeleteAlias on one of their aliases. Needs CloudTrail management events (security baseline). | `bool` | `false` | no |
| <a name="input_enable_log_delivery"></a> [enable\_log\_delivery](#input\_enable\_log\_delivery) | Let the vended logs delivery service (delivery.logs.amazonaws.com, used by WAF and API Gateway logs sent to S3) use the logs key, restricted to delivery sources of this account. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name, applied as the Environment tag on every key (the CI apply roles require it on kms:CreateKey). | `string` | n/a | yes |
| <a name="input_guardduty_malware_protection_role_arns"></a> [guardduty\_malware\_protection\_role\_arns](#input\_guardduty\_malware\_protection\_role\_arns) | ARNs of the IAM roles used by GuardDuty Malware Protection for S3 to scan and tag objects of SSE-KMS buckets. The roles must exist. Empty disables the statement. | `list(string)` | `[]` | no |
| <a name="input_keys"></a> [keys](#input\_keys) | Customer managed keys to create, one per domain, keyed by domain name. The alias is alias/<name\_prefix>-<domain>. The service grants below target the domains "logs", "data" and "ai" and need the matching key to exist. A key flagged edge = true additionally lets CloudFront use it through an origin access control, for any distribution of this account (aws:SourceArn ArnLike on the account's distributions): it exists so that the key can be created before the distribution, without a dependency on the stack that owns it. Flag only a key that encrypts nothing but buckets served by CloudFront, whose bucket policy pins the distribution. | <pre>map(object({<br/>    description = string<br/>    edge        = optional(bool, false)<br/>  }))</pre> | <pre>{<br/>  "ai": {<br/>    "description": "Encrypts the AI assistant data: Bedrock Knowledge Base sources and ingestion"<br/>  },<br/>  "data": {<br/>    "description": "Encrypts application data at rest: DynamoDB tables, SQS queues, S3 buckets"<br/>  },<br/>  "logs": {<br/>    "description": "Encrypts logs: CloudWatch Logs log groups, CloudTrail, AWS Config"<br/>  }<br/>}</pre> | no |
| <a name="input_kms_deletion_window_in_days"></a> [kms\_deletion\_window\_in\_days](#input\_kms\_deletion\_window\_in\_days) | Waiting period, in days, before a key is deleted after a deletion request. Must be 30 (the maximum) when environment is "prod". | `number` | n/a | yes |
| <a name="input_log_group_name_patterns"></a> [log\_group\_name\_patterns](#input\_log\_group\_name\_patterns) | Log group name patterns, in addition to "<name\_prefix>-*", that CloudWatch Logs may encrypt with the logs key (for example "/aws/lambda/sc-dev-*"). Each pattern needs at least 3 literal characters, may end with "*" and must contain "<name\_prefix>-" (the account is shared by the environments). | `list(string)` | `[]` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name and alias, <project>-<env> (for example "sc-dev"). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alias_arns"></a> [alias\_arns](#output\_alias\_arns) | ARN of the alias of each key, by domain. |
| <a name="output_alias_names"></a> [alias\_names](#output\_alias\_names) | Alias of each key, by domain (alias/<name\_prefix>-<domain>). |
| <a name="output_deletion_alert_rule_arn"></a> [deletion\_alert\_rule\_arn](#output\_deletion\_alert\_rule\_arn) | ARN of the key deletion alert EventBridge rule, or null when alerts are disabled. Use it as aws:SourceArn in the alert topic policy. |
| <a name="output_key_arns"></a> [key\_arns](#output\_key\_arns) | ARN of each key, by domain. The foundation stack publishes it to SSM at /smartcampus/<env>/foundation/kms\_<domain>\_key\_arn (EN-14 AC4); the module itself creates no SSM parameter. |
| <a name="output_key_ids"></a> [key\_ids](#output\_key\_ids) | ID of each key, by domain. |
<!-- END_TF_DOCS -->

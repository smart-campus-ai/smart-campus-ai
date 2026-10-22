# kpi

Table DynamoDB `kpi` (EN-46) : agrégats journaliers (compteurs par jour, statut et catégorie, sommes de temps de résolution), alimentée depuis le stream de `tickets` par `kpi-aggregator`. Le module porte aussi le mapping stream → fonction (filtre d'événements, report des échecs par élément, bissection, destination d'échec SQS) et la politique IAM de l'agrégateur, à attacher au rôle créé par `lambda-service`.

## Contrat du handler kpi-aggregator (SE)

Le filtre de stream ne peut pas exprimer `OldImage.status != NewImage.status`. Le handler doit donc :

1. **Ignorer les MODIFY sans changement de statut** : comparer `OldImage.status` et `NewImage.status`, ne traiter que les records où ils diffèrent.
2. **Déduplication par sequence number** : chaque record DynamoDB porte un `dynamodb.SequenceNumber` unique et croissant. Le handler doit l'utiliser pour garantir l'idempotence (replay safety) :
   - Stocker le dernier sequence number traité par partition key (ou globalement si l'ordre importe).
   - Ignorer les records avec un sequence number déjà vu ou antérieur.
3. **Mise à jour atomique** : utiliser `UpdateItem` avec une expression conditionnelle sur l'aggregate existant (ou créer s'il n'existe pas). Un seul update par aggregate par événement.
4. **Batch item failures** : en cas d'erreur sur un record, le signaler dans `batchItemFailures` pour que seul ce record soit réessayé (pas tout le batch).

Ces règles sont documentées ici car le module infra ne peut pas les appliquer ; le code SE est responsable de l'implémentation.

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
| [aws_dynamodb_table.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_iam_policy.aggregator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_lambda_event_source_mapping.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_event_source_mapping) | resource |
| [aws_sqs_queue.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_policy.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [aws_iam_policy_document.aggregator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.dlq_tls](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_batch_size"></a> [batch\_size](#input\_batch\_size) | Maximum number of stream records sent to one invocation. | `number` | `100` | no |
| <a name="input_dlq_retention_seconds"></a> [dlq\_retention\_seconds](#input\_dlq\_retention\_seconds) | Retention in seconds of the messages in the failure queue (60 s to 14 days). | `number` | `1209600` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Protect the kpi table against deletion. Must be true in prod; no default so that each environment decides explicitly. | `bool` | n/a | yes |
| <a name="input_function_name"></a> [function\_name](#input\_function\_name) | Name or ARN of the kpi-aggregator Lambda function, qualified with the :live alias (for example "sc-dev-kpi-aggregator:live" or the alias ARN) so that the mapping targets the live alias. | `string` | n/a | yes |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the customer-managed KMS key ("data" domain, EN-14) that encrypts the kpi table and the failure queue, and that protects the tickets stream. The key policy must allow DynamoDB and SQS to use it. | `string` | n/a | yes |
| <a name="input_maximum_batching_window_in_seconds"></a> [maximum\_batching\_window\_in\_seconds](#input\_maximum\_batching\_window\_in\_seconds) | Maximum time in seconds to gather records before invoking the function. | `number` | `5` | no |
| <a name="input_maximum_record_age_in_seconds"></a> [maximum\_record\_age\_in\_seconds](#input\_maximum\_record\_age\_in\_seconds) | Maximum age in seconds of a record the mapping still processes; older records go to the failure queue. Bounded for the same reason as the retries. | `number` | `86400` | no |
| <a name="input_maximum_retry_attempts"></a> [maximum\_retry\_attempts](#input\_maximum\_retry\_attempts) | Number of retries of a failing batch before it is sent to the failure queue. Bounded so that a poison record cannot block a shard. | `number` | `3` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, in the form sc-<env> (for example "sc-dev"). | `string` | n/a | yes |
| <a name="input_partition_key_name"></a> [partition\_key\_name](#input\_partition\_key\_name) | Name of the partition key attribute (string) of the kpi table, for example the aggregate day. Aligned with SE in packages/contracts. | `string` | `"pk"` | no |
| <a name="input_sort_key_name"></a> [sort\_key\_name](#input\_sort\_key\_name) | Name of the sort key attribute (string) of the kpi table, for example the aggregate dimension (status, category). | `string` | `"sk"` | no |
| <a name="input_starting_position"></a> [starting\_position](#input\_starting\_position) | Where the mapping starts reading the stream: TRIM\_HORIZON (oldest available record, no event lost) or LATEST. | `string` | `"TRIM_HORIZON"` | no |
| <a name="input_stream_arn"></a> [stream\_arn](#input\_stream\_arn) | ARN of the tickets table stream (output stream\_arn of tickets-store, NEW\_AND\_OLD\_IMAGES). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_ticket_meta_sort_key_value"></a> [ticket\_meta\_sort\_key\_value](#input\_ticket\_meta\_sort\_key\_value) | Sort key value of the ticket item itself in the tickets table (the audit trail items use another value). | `string` | `"META"` | no |
| <a name="input_ticket_sort_key_name"></a> [ticket\_sort\_key\_name](#input\_ticket\_sort\_key\_name) | Name of the sort key attribute of the tickets table, used by the event filter to keep ticket items only. | `string` | `"sk"` | no |
| <a name="input_ticket_status_attribute_name"></a> [ticket\_status\_attribute\_name](#input\_ticket\_status\_attribute\_name) | Name of the status attribute of the ticket item, used by the event filter. | `string` | `"status"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_aggregator_policy_arn"></a> [aggregator\_policy\_arn](#output\_aggregator\_policy\_arn) | ARN of the IAM policy to attach to the kpi-aggregator role: stream read, kpi write, failure destination, KMS use. No access to the tickets table. |
| <a name="output_dlq_arn"></a> [dlq\_arn](#output\_dlq\_arn) | ARN of the SQS queue receiving the batches the stream mapping could not process (for the DLQ depth alarm). |
| <a name="output_dlq_name"></a> [dlq\_name](#output\_dlq\_name) | Name of the failure queue (CloudWatch dimension QueueName for the DLQ depth alarm). |
| <a name="output_event_source_mapping_uuid"></a> [event\_source\_mapping\_uuid](#output\_event\_source\_mapping\_uuid) | UUID of the tickets stream -> kpi-aggregator event source mapping. |
| <a name="output_table_arn"></a> [table\_arn](#output\_table\_arn) | ARN of the kpi table, for the IAM policy of the kpi (read) function. |
| <a name="output_table_name"></a> [table\_name](#output\_table\_name) | Name of the kpi table (KPI\_TABLE environment variable of kpi and kpi-aggregator). |
<!-- END_TF_DOCS -->

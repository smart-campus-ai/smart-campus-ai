# chat-sessions

Table DynamoDB des historiques de chat de l'assistant (US02). Elle est séparée de la table `tickets` car la rétention est différente : les conversations contiennent des données personnelles et sont purgées automatiquement (US08).

## Rétention RGPD (US08)

- Le TTL est activé sur l'attribut `expiresAt` (nom configurable). DynamoDB supprime les items dont l'epoch (en secondes) est dépassé. La suppression est asynchrone et peut prendre quelques jours : le service `chat` doit aussi ignorer à la lecture les items expirés.
- Le module ne calcule pas le TTL. Le service `chat` écrit `expiresAt = dernière activité + retention_days` à chaque écriture ; la sortie `retention_days` lui sert de configuration.
- La valeur par défaut de `retention_days` (30 jours) est à valider avec le PO et le BA (US08). Elle se règle dans le `tfvars` de l'environnement.
- Voie de suppression à la demande : `DeleteItem` (autorisé par `access_policy_json`) sur les sessions d'un utilisateur, retrouvées avec l'index `by-owner`.
- Pas de stream par défaut (`enable_stream = false`) : aucune copie des transcriptions hors de la table. PITR activé (35 jours de restauration, fixés par DynamoDB) : une transcription supprimée reste donc récupérable dans cette fenêtre.

## Schéma de clés

- Table : `sessionId` (partition) et `ts` (tri), chaînes de caractères, configurables.
- Index `by-owner` (`enable_owner_index`, actif par défaut) : `sub` (partition) et `createdAt` (tri). Il liste toutes les sessions d'un utilisateur avec un `Query`, sans `Scan` (EN-53-AC3). L'identité vient toujours du `sub` du JWT, jamais de la requête.

## Droits du service `chat`

La sortie `access_policy_json` donne les droits minimaux : `GetItem`, `BatchGetItem`, `PutItem`, `UpdateItem`, `DeleteItem` et `Query` sur la table et ses index, sans `Scan` (EN-53-AC4). La table étant chiffrée par une clé gérée par le client, DynamoDB utilise des grants sur la clé : le rôle de la fonction n'a pas besoin de permissions KMS.

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
| [aws_iam_policy_document.access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_deletion_protection_enabled"></a> [deletion\_protection\_enabled](#input\_deletion\_protection\_enabled) | Protect the table against deletion. Keep it true in prod; set it to false in dev only when the table must be destroyed. | `bool` | `true` | no |
| <a name="input_enable_owner_index"></a> [enable\_owner\_index](#input\_enable\_owner\_index) | Create the "by-owner" global secondary index, which lists every session of a user (JWT "sub") with a Query instead of a Scan (EN-53-AC3). The default keys are keyed by session, so this index is what serves the per-user listing. | `bool` | `true` | no |
| <a name="input_enable_stream"></a> [enable\_stream](#input\_enable\_stream) | Enable a DynamoDB stream on the table. Off by default: no consumer reads chat sessions, and a stream would copy personal data outside the TTL purge path. | `bool` | `false` | no |
| <a name="input_hash_key"></a> [hash\_key](#input\_hash\_key) | Name of the partition key attribute. The default is one item collection per chat session. | `string` | `"sessionId"` | no |
| <a name="input_hash_key_type"></a> [hash\_key\_type](#input\_hash\_key\_type) | DynamoDB type of the partition key: S (string), N (number) or B (binary). | `string` | `"S"` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the customer-managed KMS key ("data" key, EN-14) that encrypts the table at rest. Chat transcripts are personal data, hence the data key shared with tickets. An alias ARN is not accepted by DynamoDB. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, in the form sc-<env> (for example "sc-dev"). | `string` | n/a | yes |
| <a name="input_owner_index_hash_key"></a> [owner\_index\_hash\_key](#input\_owner\_index\_hash\_key) | Attribute holding the owner (Cognito "sub") of a session; partition key of the "by-owner" index. Always a string. | `string` | `"sub"` | no |
| <a name="input_owner_index_range_key"></a> [owner\_index\_range\_key](#input\_owner\_index\_range\_key) | Attribute used to sort the sessions of an owner (creation time, ISO 8601 string); sort key of the "by-owner" index. Always a string. | `string` | `"createdAt"` | no |
| <a name="input_range_key"></a> [range\_key](#input\_range\_key) | Name of the sort key attribute, or null for a table with a partition key only. The default orders the messages of a session by timestamp (ISO 8601 string). | `string` | `"ts"` | no |
| <a name="input_range_key_type"></a> [range\_key\_type](#input\_range\_key\_type) | DynamoDB type of the sort key: S (string), N (number) or B (binary). Ignored when range\_key is null. | `string` | `"S"` | no |
| <a name="input_retention_days"></a> [retention\_days](#input\_retention\_days) | Retention of a chat session, in days, applied by the chat service when it sets the TTL attribute on write (expiresAt = last activity + retention\_days). The value is still to be validated for GDPR (US08). Exposed as an output so that the service receives it as configuration; the table itself only enforces the TTL attribute. | `number` | `30` | no |
| <a name="input_stream_view_type"></a> [stream\_view\_type](#input\_stream\_view\_type) | Content of the stream records. Only used when enable\_stream is true. | `string` | `"NEW_AND_OLD_IMAGES"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_ttl_attribute_name"></a> [ttl\_attribute\_name](#input\_ttl\_attribute\_name) | Name of the TTL attribute. Items are purged automatically once the epoch time (in seconds) it holds has passed, which implements the GDPR retention of chat transcripts (US08). | `string` | `"expiresAt"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_policy_json"></a> [access\_policy\_json](#output\_access\_policy\_json) | IAM policy document (JSON) granting item access (Get, BatchGet, Put, Update, Delete, Query; no Scan) on the table and its indexes, to attach to the role of the chat function. |
| <a name="output_hash_key"></a> [hash\_key](#output\_hash\_key) | Name of the partition key attribute. |
| <a name="output_index_arns"></a> [index\_arns](#output\_index\_arns) | ARNs of the global secondary indexes (empty when enable\_owner\_index is false), for IAM policies written outside this module. |
| <a name="output_owner_index_name"></a> [owner\_index\_name](#output\_owner\_index\_name) | Name of the index that lists the sessions of an owner, or null when enable\_owner\_index is false. |
| <a name="output_range_key"></a> [range\_key](#output\_range\_key) | Name of the sort key attribute, or null when the table has no sort key. |
| <a name="output_retention_days"></a> [retention\_days](#output\_retention\_days) | Configured retention of a chat session, in days; the chat function uses it to compute the TTL attribute. |
| <a name="output_stream_arn"></a> [stream\_arn](#output\_stream\_arn) | ARN of the table stream, or null when enable\_stream is false. |
| <a name="output_table_arn"></a> [table\_arn](#output\_table\_arn) | ARN of the chat-sessions table. |
| <a name="output_table_name"></a> [table\_name](#output\_table\_name) | Name of the chat-sessions table (environment variable of the chat function). |
| <a name="output_ttl_attribute_name"></a> [ttl\_attribute\_name](#output\_ttl\_attribute\_name) | Name of the TTL attribute; the chat function writes the expiry (epoch seconds) in it. |
<!-- END_TF_DOCS -->

# tickets-store

Table DynamoDB `tickets` (EN-42) : collection d'éléments par ticket (`TICKET#id` / `META`, `EVENT#ts`), GSI propriétaire et statut, stream `NEW_AND_OLD_IMAGES`, PITR, chiffrement par la clé KMS `data`.

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
| [aws_dynamodb_contributor_insights.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_contributor_insights) | resource |
| [aws_dynamodb_table.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_created_at_attribute_name"></a> [created\_at\_attribute\_name](#input\_created\_at\_attribute\_name) | Name of the attribute holding the creation date (ISO 8601 string); sort key of both GSIs. | `string` | `"createdAt"` | no |
| <a name="input_enable_contributor_insights"></a> [enable\_contributor\_insights](#input\_enable\_contributor\_insights) | Enable CloudWatch Contributor Insights on the table and its indexes to find hot keys. Off by default: it is billed per event. | `bool` | `false` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Protect the table against deletion. Must be true in prod; no default so that each environment decides explicitly. | `bool` | n/a | yes |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the customer-managed KMS key ("data" domain, EN-14) that encrypts the table at rest. The key policy must allow DynamoDB to use it. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, in the form sc-<env> (for example "sc-dev"). | `string` | n/a | yes |
| <a name="input_owner_attribute_name"></a> [owner\_attribute\_name](#input\_owner\_attribute\_name) | Name of the attribute holding the owner's Cognito sub (string); partition key of the owner GSI. | `string` | `"ownerSub"` | no |
| <a name="input_partition_key_name"></a> [partition\_key\_name](#input\_partition\_key\_name) | Name of the partition key attribute (string), shared by every item of a ticket collection (TICKET#<id>). Aligned with SE in packages/contracts. | `string` | `"pk"` | no |
| <a name="input_sort_key_name"></a> [sort\_key\_name](#input\_sort\_key\_name) | Name of the sort key attribute (string): META for the ticket, EVENT#<timestamp> for the audit trail. | `string` | `"sk"` | no |
| <a name="input_status_attribute_name"></a> [status\_attribute\_name](#input\_status\_attribute\_name) | Name of the attribute holding the ticket status (string); partition key of the status GSI. | `string` | `"status"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_ttl_attribute_name"></a> [ttl\_attribute\_name](#input\_ttl\_attribute\_name) | Name of the attribute (epoch seconds) after which DynamoDB expires an item. Null disables TTL. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_index_arns"></a> [index\_arns](#output\_index\_arns) | ARNs of the global secondary indexes keyed by index name (by-owner, by-status), for the Query permission of the functions. |
| <a name="output_owner_index_name"></a> [owner\_index\_name](#output\_owner\_index\_name) | Name of the owner GSI (owner sub + creation date). |
| <a name="output_status_index_name"></a> [status\_index\_name](#output\_status\_index\_name) | Name of the status GSI (status + creation date). |
| <a name="output_stream_arn"></a> [stream\_arn](#output\_stream\_arn) | ARN of the table stream (NEW\_AND\_OLD\_IMAGES), consumed by notifier and kpi-aggregator. |
| <a name="output_table_arn"></a> [table\_arn](#output\_table\_arn) | ARN of the tickets table, for the IAM policies of the functions (table-level actions). |
| <a name="output_table_name"></a> [table\_name](#output\_table\_name) | Name of the tickets table (TICKETS\_TABLE environment variable of the functions). |
<!-- END_TF_DOCS -->

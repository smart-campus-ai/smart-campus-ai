# knowledge-base

Bedrock Knowledge Base de l'assistant (US02, US07, ADR-0007) : bucket des documents sources, vector store S3 Vectors (bucket + index), data source sur le préfixe des documents avec découpage en chunks, et rôle de service de la Knowledge Base.

Tout est chiffré par la clé `ai` (EN-14), passée en entrée. Seuls les principaux de `writer_principal_arns` peuvent écrire dans le bucket des sources. Interfaces vers la stack platform (EN-51) :

- AC4 : avec `enable_ingestion_notification`, les créations et suppressions d'objets sous `source_prefix` invoquent la fonction `ingestion_function_arn` (`kb-sync`) ; la permission Lambda est limitée par `aws:SourceArn` (bucket) et `aws:SourceAccount`. L'ARN de la fonction se construit à partir de son nom pour éviter un cycle de dépendance (la fonction reçoit `knowledge_base_id` et `data_source_id`).
- AC5 : les sorties `policy_json_retrieve` (`chat` : `bedrock:Retrieve` sur la Knowledge Base et `bedrock:InvokeModel` sur le profil d'inférence et ses modèles sous-jacents) et `policy_json_sync` (`kb-sync` : `StartIngestionJob` et `GetIngestionJob`) sont à attacher aux rôles des fonctions. Les régions des ARN de modèles sont explicites, sans joker.

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
| [aws_bedrockagent_data_source.sources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagent_data_source) | resource |
| [aws_bedrockagent_knowledge_base.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrockagent_knowledge_base) | resource |
| [aws_iam_role.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_lambda_permission.ingestion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_s3_bucket.sources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.sources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_notification.sources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_notification) | resource |
| [aws_s3_bucket_ownership_controls.sources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.sources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.sources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.sources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.sources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3vectors_index.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3vectors_index) | resource |
| [aws_s3vectors_vector_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3vectors_vector_bucket) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.retrieve](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.service_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.sources_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.sync](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_abort_incomplete_multipart_upload_days"></a> [abort\_incomplete\_multipart\_upload\_days](#input\_abort\_incomplete\_multipart\_upload\_days) | Number of days after which an incomplete multipart upload is aborted. | `number` | `7` | no |
| <a name="input_chunking_max_tokens"></a> [chunking\_max\_tokens](#input\_chunking\_max\_tokens) | Maximum number of tokens in a chunk (fixed-size chunking). | `number` | `300` | no |
| <a name="input_chunking_overlap_percentage"></a> [chunking\_overlap\_percentage](#input\_chunking\_overlap\_percentage) | Percentage of tokens shared between two consecutive chunks (fixed-size chunking). | `number` | `20` | no |
| <a name="input_distance_metric"></a> [distance\_metric](#input\_distance\_metric) | Distance metric of the vector index similarity search. Cannot be changed without recreating the index. | `string` | `"cosine"` | no |
| <a name="input_embedding_model_additional_arns"></a> [embedding\_model\_additional\_arns](#input\_embedding\_model\_additional\_arns) | Foundation model ARNs the service role may also invoke. Required when embedding\_model\_arn is an inference profile: list the underlying foundation model in each region the profile routes to, one explicit ARN per region (no wildcard region). Leave empty when embedding\_model\_arn is a foundation model. | `list(string)` | `[]` | no |
| <a name="input_embedding_model_arn"></a> [embedding\_model\_arn](#input\_embedding\_model\_arn) | ARN of the embedding model used to vectorize the documents and the queries: a foundation model (arn:aws:bedrock:<region>::foundation-model/<id>) or a cross-region inference profile (arn:aws:bedrock:<region>:<account id>:inference-profile/<id>), for example an EU profile so that inference stays in the EU. | `string` | n/a | yes |
| <a name="input_enable_embedding_model_configuration"></a> [enable\_embedding\_model\_configuration](#input\_enable\_embedding\_model\_configuration) | Pass vector\_dimension and the FLOAT32 data type to the embedding model. Turn off for models that do not accept a dimension setting (for example Titan Text Embeddings V1, fixed at 1536). | `bool` | `true` | no |
| <a name="input_enable_ingestion_notification"></a> [enable\_ingestion\_notification](#input\_enable\_ingestion\_notification) | Send the S3 object-created and object-removed events under source\_prefix to ingestion\_function\_arn (EN-51 AC4), and allow S3 to invoke it. | `bool` | `true` | no |
| <a name="input_inference_model_arns"></a> [inference\_model\_arns](#input\_inference\_model\_arns) | Foundation model ARNs underlying inference\_profile\_arn: one explicit ARN for each region the profile routes to (no wildcard region). Bedrock authorizes the invocation on the profile and on each of these models. | `list(string)` | n/a | yes |
| <a name="input_inference_profile_arn"></a> [inference\_profile\_arn](#input\_inference\_profile\_arn) | ARN of the cross-region inference profile the chat function invokes to generate answers (for example a US system profile in the workshop region). Scoped in policy\_json\_retrieve. | `string` | n/a | yes |
| <a name="input_ingestion_function_arn"></a> [ingestion\_function\_arn](#input\_ingestion\_function\_arn) | ARN of the Lambda function (kb-sync) invoked on document creation and deletion under source\_prefix. Required when enable\_ingestion\_notification is true; the function is owned by the platform stack. Its environment needs knowledge\_base\_id and data\_source\_id, so build this ARN from the function name instead of the function resource to avoid a dependency cycle. | `string` | `null` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the customer-managed KMS key ("ai" domain, EN-14) that encrypts the source bucket, the vector bucket, the vector index and the data transient during ingestion. Its key policy must let the S3 Vectors service and the knowledge base service role use it. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, in the form sc-<env> (for example "sc-dev"). | `string` | n/a | yes |
| <a name="input_noncurrent_version_expiration_days"></a> [noncurrent\_version\_expiration\_days](#input\_noncurrent\_version\_expiration\_days) | Number of days after which noncurrent versions of the source documents are permanently deleted. | `number` | `90` | no |
| <a name="input_permissions_boundary_arn"></a> [permissions\_boundary\_arn](#input\_permissions\_boundary\_arn) | ARN of the project permissions boundary policy attached to the knowledge base service role. null attaches no boundary: only for the workshop exception of ADR-0014 (stacks enforce its scope and expiry). | `string` | n/a | yes |
| <a name="input_source_prefix"></a> [source\_prefix](#input\_source\_prefix) | Key prefix of the source documents in the bucket. The data source only ingests objects under this prefix, and the service role can only read objects under it. | `string` | `"documents/"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_vector_dimension"></a> [vector\_dimension](#input\_vector\_dimension) | Number of dimensions of the embedding vectors. Must be a size the embedding model produces (for example 256, 512 or 1024 for Titan Text Embeddings V2). Cannot be changed without recreating the index. | `number` | n/a | yes |
| <a name="input_writer_principal_arns"></a> [writer\_principal\_arns](#input\_writer\_principal\_arns) | IAM role or user ARNs that are the only principals allowed to write or delete objects in the source bucket (for example the application deploy role). Every other principal, including the account administrators, is denied by the bucket policy. The knowledge base service role only reads and needs no entry. | `list(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_data_source_id"></a> [data\_source\_id](#output\_data\_source\_id) | ID of the data source on the source bucket (StartIngestionJob). |
| <a name="output_knowledge_base_arn"></a> [knowledge\_base\_arn](#output\_knowledge\_base\_arn) | ARN of the knowledge base, scoped in the chat and kb-sync policies (EN-51 AC5). |
| <a name="output_knowledge_base_id"></a> [knowledge\_base\_id](#output\_knowledge\_base\_id) | ID of the knowledge base (Retrieve calls and ingestion jobs). |
| <a name="output_policy_json_retrieve"></a> [policy\_json\_retrieve](#output\_policy\_json\_retrieve) | IAM policy document for the chat function: bedrock:Retrieve on the knowledge base and bedrock:InvokeModel on the inference profile and its underlying models (EN-51 AC5). |
| <a name="output_policy_json_sync"></a> [policy\_json\_sync](#output\_policy\_json\_sync) | IAM policy document for the kb-sync function: StartIngestionJob and GetIngestionJob on the knowledge base (EN-51 AC5). |
| <a name="output_service_role_arn"></a> [service\_role\_arn](#output\_service\_role\_arn) | ARN of the knowledge base service role. |
| <a name="output_service_role_name"></a> [service\_role\_name](#output\_service\_role\_name) | Name of the knowledge base service role. |
| <a name="output_source_bucket_arn"></a> [source\_bucket\_arn](#output\_source\_bucket\_arn) | ARN of the source documents bucket, scoped in the writer and kb-sync policies. |
| <a name="output_source_bucket_name"></a> [source\_bucket\_name](#output\_source\_bucket\_name) | Name of the source documents bucket (target of the S3 event notification to kb-sync). |
| <a name="output_source_prefix"></a> [source\_prefix](#output\_source\_prefix) | Key prefix of the source documents (filter of the S3 event notification). |
| <a name="output_vector_bucket_arn"></a> [vector\_bucket\_arn](#output\_vector\_bucket\_arn) | ARN of the S3 Vectors vector bucket. |
| <a name="output_vector_bucket_name"></a> [vector\_bucket\_name](#output\_vector\_bucket\_name) | Name of the S3 Vectors vector bucket. |
| <a name="output_vector_index_arn"></a> [vector\_index\_arn](#output\_vector\_index\_arn) | ARN of the S3 Vectors index. |
| <a name="output_vector_index_name"></a> [vector\_index\_name](#output\_vector\_index\_name) | Name of the S3 Vectors index. |
<!-- END_TF_DOCS -->

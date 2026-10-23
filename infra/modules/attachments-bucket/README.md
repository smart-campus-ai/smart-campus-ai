# attachments-bucket

Bucket S3 des pièces jointes des tickets (EN-43) : privé, chiffré par la clé KMS `data`, téléversement par POST pré-signé uniquement (10 Mo maximum, JPG/PNG, voir le contrat ci-dessous), analyse optionnelle par GuardDuty Malware Protection for S3. Quand l'analyse est activée, seuls les objets marqués `GuardDutyMalwareScanStatus=NO_THREATS_FOUND` peuvent être lus.

## Contrat du POST pré-signé (EN-43 AC2)

Le POST pré-signé est signé à l'exécution par le code de `tickets` (SE) ; le bucket n'impose pas ces limites lui-même. CORS n'autorise que `GET` (téléchargement pré-signé) et `POST` : le `PUT` est exclu pour ne pas contourner la policy du POST.

Le code doit générer **une policy signée par type de contenu** de la sortie `allowed_content_types`, avec les conditions suivantes :

| Condition | Valeur |
| --------- | ------ |
| `["content-length-range", 1, <max_upload_bytes>]` | sortie `max_upload_bytes` (10485760 = 10 Mio) |
| `{"Content-Type": "<type>"}` | égalité stricte avec un seul élément de `allowed_content_types` (`image/jpeg`, `image/png`), jamais `starts-with` |
| `["starts-with", "$key", "<attachments_prefix><sub>/"]` | sortie `attachments_prefix` ; la clé est construite côté serveur à partir du `sub` du JWT |
| `{"bucket": "<bucket_name>"}` | sortie `bucket_name` |

Le POST ne doit pas autoriser le champ `tagging` : la bucket policy refuse de toute façon l'écriture du tag `GuardDutyMalwareScanStatus` à tout autre principal que le rôle d'analyse.

Le rôle `tickets` reçoit la sortie `policy_json_tickets_rw` : `s3:GetObject` et `s3:PutObject` limités à `<bucket>/<attachments_prefix>*`. Elle ne contient pas les droits KMS : la clé `data` doit les accorder au rôle (EN-14).

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
| [aws_guardduty_malware_protection_plan.attachments](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_malware_protection_plan) | resource |
| [aws_iam_role.malware](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.malware](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.attachments](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_cors_configuration.attachments](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_cors_configuration) | resource |
| [aws_s3_bucket_lifecycle_configuration.attachments](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.attachments](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.attachments](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.attachments](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.attachments](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.attachments](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.malware_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.malware_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.tickets_rw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_abort_incomplete_multipart_upload_days"></a> [abort\_incomplete\_multipart\_upload\_days](#input\_abort\_incomplete\_multipart\_upload\_days) | Number of days after which an incomplete multipart upload is aborted. | `number` | `7` | no |
| <a name="input_allowed_content_types"></a> [allowed\_content\_types](#input\_allowed\_content\_types) | Content types accepted for an attachment: the values the presigned POST policy must allow in its Content-Type condition (one signed policy per type). JPEG and PNG only. | `list(string)` | <pre>[<br/>  "image/jpeg",<br/>  "image/png"<br/>]</pre> | no |
| <a name="input_allowed_origins"></a> [allowed\_origins](#input\_allowed\_origins) | Origins allowed to call the bucket from a browser (presigned POST uploads, GET downloads): the CloudFront URL of the SPA, plus http://localhost:<port> in dev. Wildcards are refused. | `list(string)` | n/a | yes |
| <a name="input_attachments_prefix"></a> [attachments\_prefix](#input\_attachments\_prefix) | Key prefix under which the attachments are stored. The "tickets" role policy (policy\_json\_tickets\_rw) is limited to this prefix, and the presigned POST key must start with it. | `string` | `"attachments/"` | no |
| <a name="input_cors_max_age_seconds"></a> [cors\_max\_age\_seconds](#input\_cors\_max\_age\_seconds) | Time, in seconds, browsers may cache the CORS preflight response. | `number` | `3000` | no |
| <a name="input_enable_malware_protection"></a> [enable\_malware\_protection](#input\_enable\_malware\_protection) | Create the GuardDuty Malware Protection plan for S3 (with its service role) and deny reads of objects that are not tagged GuardDutyMalwareScanStatus=NO\_THREATS\_FOUND. Requires GuardDuty Malware Protection for S3 in the region (EN-11). Enabled by default so that unscanned objects are never served. Setting it to false removes the read deny and serves every object as is: only do it where the service is unavailable, with an ADR. | `bool` | `true` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the customer-managed KMS key ("data" key, EN-14) that encrypts the attachments. It is the bucket default key and the only key accepted by the bucket policy. Its key policy must let the account use it through IAM, and the malware protection role when enable\_malware\_protection is true. | `string` | n/a | yes |
| <a name="input_malware_protection_object_prefixes"></a> [malware\_protection\_object\_prefixes](#input\_malware\_protection\_object\_prefixes) | Key prefixes scanned by the malware protection plan (at most 5). Empty scans the whole bucket. | `list(string)` | `[]` | no |
| <a name="input_max_upload_bytes"></a> [max\_upload\_bytes](#input\_max\_upload\_bytes) | Maximum size, in bytes, of an uploaded attachment: the upper bound of the content-length-range condition that the presigned POST policy must carry. 10 MiB at most (EN-43 AC2). | `number` | `10485760` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, "sc-<env>" (for example "sc-dev"). | `string` | n/a | yes |
| <a name="input_noncurrent_version_expiration_days"></a> [noncurrent\_version\_expiration\_days](#input\_noncurrent\_version\_expiration\_days) | Number of days after which noncurrent object versions are permanently deleted. | `number` | `30` | no |
| <a name="input_object_expiration_days"></a> [object\_expiration\_days](#input\_object\_expiration\_days) | Retention of the attachments (GDPR): number of days after creation at which current objects expire, aligned with the ticket retention. Required, no default. | `number` | n/a | yes |
| <a name="input_permissions_boundary_arn"></a> [permissions\_boundary\_arn](#input\_permissions\_boundary\_arn) | ARN of the workload permissions boundary attached to the malware protection service role. null attaches no boundary: only for the workshop exception of ADR-0014 (stacks enforce its scope and expiry). | `string` | `null` | no |
| <a name="input_quarantine_expiration_days"></a> [quarantine\_expiration\_days](#input\_quarantine\_expiration\_days) | Number of days after which objects under quarantine\_prefix expire. null disables the rule. | `number` | `null` | no |
| <a name="input_quarantine_prefix"></a> [quarantine\_prefix](#input\_quarantine\_prefix) | Key prefix where objects waiting for, or failing, the malware scan are kept (the area the presigned POST uploads to). Only used when quarantine\_expiration\_days is set. | `string` | `"quarantine/"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_allowed_content_types"></a> [allowed\_content\_types](#output\_allowed\_content\_types) | Content types accepted for an attachment: values of the Content-Type condition of the presigned POST policy. |
| <a name="output_attachments_prefix"></a> [attachments\_prefix](#output\_attachments\_prefix) | Key prefix of the attachments; the key of the presigned POST must start with it. |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | ARN of the attachments bucket, scoped in the IAM policies of the roles that use it. |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Name of the attachments bucket (BUCKET env var of "tickets"). |
| <a name="output_bucket_regional_domain_name"></a> [bucket\_regional\_domain\_name](#output\_bucket\_regional\_domain\_name) | Regional domain name of the attachments bucket (target of the presigned POST). |
| <a name="output_malware_protection_plan_arn"></a> [malware\_protection\_plan\_arn](#output\_malware\_protection\_plan\_arn) | ARN of the GuardDuty Malware Protection plan, null when enable\_malware\_protection is false. |
| <a name="output_malware_protection_role_arn"></a> [malware\_protection\_role\_arn](#output\_malware\_protection\_role\_arn) | ARN of the malware protection service role, null when enable\_malware\_protection is false. |
| <a name="output_max_upload_bytes"></a> [max\_upload\_bytes](#output\_max\_upload\_bytes) | Maximum size of an attachment in bytes (10485760 = 10 MiB): upper bound of the content-length-range condition of the presigned POST policy. |
| <a name="output_policy_json_tickets_rw"></a> [policy\_json\_tickets\_rw](#output\_policy\_json\_tickets\_rw) | IAM policy document (JSON) for the "tickets" role: PutObject and GetObject limited to the attachments prefix of the bucket. Attach it to the role in the module that owns the role. |
| <a name="output_scan_status_clean_tag_value"></a> [scan\_status\_clean\_tag\_value](#output\_scan\_status\_clean\_tag\_value) | Value of the scan tag on an object with no threat found; the only objects that can be read when malware protection is enabled. |
| <a name="output_scan_status_tag_key"></a> [scan\_status\_tag\_key](#output\_scan\_status\_tag\_key) | Key of the object tag written by GuardDuty with the scan result. |
<!-- END_TF_DOCS -->

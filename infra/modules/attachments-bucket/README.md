# attachments-bucket

Bucket S3 des pièces jointes des tickets (EN-43) : privé, chiffré par la clé KMS `data`, téléversement par POST pré-signé (10 Mo maximum, JPG/PNG), analyse optionnelle par GuardDuty Malware Protection for S3. Quand l'analyse est activée, seuls les objets marqués `GuardDutyMalwareScanStatus=NO_THREATS_FOUND` peuvent être lus.

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
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_abort_incomplete_multipart_upload_days"></a> [abort\_incomplete\_multipart\_upload\_days](#input\_abort\_incomplete\_multipart\_upload\_days) | Number of days after which an incomplete multipart upload is aborted. | `number` | `7` | no |
| <a name="input_allowed_origins"></a> [allowed\_origins](#input\_allowed\_origins) | Origins allowed to call the bucket from a browser (presigned POST and PUT uploads, GET downloads): the CloudFront URL of the SPA, plus http://localhost:<port> in dev. Wildcards are refused. | `list(string)` | n/a | yes |
| <a name="input_cors_max_age_seconds"></a> [cors\_max\_age\_seconds](#input\_cors\_max\_age\_seconds) | Time, in seconds, browsers may cache the CORS preflight response. | `number` | `3000` | no |
| <a name="input_enable_malware_protection"></a> [enable\_malware\_protection](#input\_enable\_malware\_protection) | Create the GuardDuty Malware Protection plan for S3 (with its service role) and deny reads of objects that are not tagged GuardDutyMalwareScanStatus=NO\_THREATS\_FOUND. Requires GuardDuty Malware Protection for S3 in the region (EN-11). Enabled by default so that unscanned objects are never served. Setting it to false removes the read deny and serves every object as is: only do it where the service is unavailable, with an ADR. | `bool` | `true` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the customer-managed KMS key ("data" key, EN-14) that encrypts the attachments. It is the bucket default key and the only key accepted by the bucket policy. Its key policy must let the account use it through IAM, and the malware protection role when enable\_malware\_protection is true. | `string` | n/a | yes |
| <a name="input_malware_protection_object_prefixes"></a> [malware\_protection\_object\_prefixes](#input\_malware\_protection\_object\_prefixes) | Key prefixes scanned by the malware protection plan (at most 5). Empty scans the whole bucket. | `list(string)` | `[]` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, "sc-<env>" (for example "sc-dev"). | `string` | n/a | yes |
| <a name="input_noncurrent_version_expiration_days"></a> [noncurrent\_version\_expiration\_days](#input\_noncurrent\_version\_expiration\_days) | Number of days after which noncurrent object versions are permanently deleted. | `number` | `30` | no |
| <a name="input_object_expiration_days"></a> [object\_expiration\_days](#input\_object\_expiration\_days) | Retention of the attachments (GDPR): number of days after creation at which current objects expire, aligned with the ticket retention. Required, no default. | `number` | n/a | yes |
| <a name="input_permissions_boundary_arn"></a> [permissions\_boundary\_arn](#input\_permissions\_boundary\_arn) | ARN of the workload permissions boundary attached to the malware protection service role (github-oidc output workload\_boundary\_arns). Required when enable\_malware\_protection is true. | `string` | `null` | no |
| <a name="input_quarantine_expiration_days"></a> [quarantine\_expiration\_days](#input\_quarantine\_expiration\_days) | Number of days after which objects under quarantine\_prefix expire. null disables the rule. | `number` | `null` | no |
| <a name="input_quarantine_prefix"></a> [quarantine\_prefix](#input\_quarantine\_prefix) | Key prefix where objects waiting for, or failing, the malware scan are kept (the area the presigned POST uploads to). Only used when quarantine\_expiration\_days is set. | `string` | `"quarantine/"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | ARN of the attachments bucket, scoped in the IAM policies of the roles that use it. |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Name of the attachments bucket (BUCKET env var of "tickets"). |
| <a name="output_bucket_regional_domain_name"></a> [bucket\_regional\_domain\_name](#output\_bucket\_regional\_domain\_name) | Regional domain name of the attachments bucket (target of the presigned POST). |
| <a name="output_malware_protection_plan_arn"></a> [malware\_protection\_plan\_arn](#output\_malware\_protection\_plan\_arn) | ARN of the GuardDuty Malware Protection plan, null when enable\_malware\_protection is false. |
| <a name="output_malware_protection_role_arn"></a> [malware\_protection\_role\_arn](#output\_malware\_protection\_role\_arn) | ARN of the malware protection service role, null when enable\_malware\_protection is false. |
| <a name="output_scan_status_clean_tag_value"></a> [scan\_status\_clean\_tag\_value](#output\_scan\_status\_clean\_tag\_value) | Value of the scan tag on an object with no threat found; the only objects that can be read when malware protection is enabled. |
| <a name="output_scan_status_tag_key"></a> [scan\_status\_tag\_key](#output\_scan\_status\_tag\_key) | Key of the object tag written by GuardDuty with the scan result. |
<!-- END_TF_DOCS -->

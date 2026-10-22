# security-baseline# security-baseline

Baseline de sécurité du compte (EN-15) : CloudTrail multi-régions, GuardDuty, Security Hub (standard FSBP), AWS Config, IAM Access Analyzer, ainsi que le durcissement au niveau compte (S3 Block Public Access, chiffrement EBS par défaut, politique de mots de passe IAM).

Chaque service est derrière un interrupteur `enable_<service>`, désactivé par défaut : le compte workshop peut déjà en fournir certains (EN-11). En compte partagé, une seule stack doit activer un service de niveau compte.

## Services fournis par le compte workshop

Le compte workshop dispose déjà des services de détection suivants (avec leurs rôles liés au service) :

- **GuardDuty** — détecteur existant
- **Security Hub** (v1 et v2) — activé avec FSBP
- **AWS Config** — enregistreur et canal de livraison actifs
- **CloudTrail** — trail multi-régions existant
- **Inspector2** — activé
- **Macie** — activé
- **IAM Access Analyzer** — analyseur de compte existant

Ne pas activer ces services dans ce module (`enable_guardduty`, `enable_securityhub`, `enable_config`, `enable_cloudtrail`, `enable_access_analyzer` restent à `false` dans les tfvars dev et prod). Les activerait créerait des ressources en conflit avec celles gérées hors OpenTofu.

CloudTrail et Config écrivent dans un bucket de logs dédié (privé, SSE-KMS avec la clé `logs` d'EN-14, TLS 1.2 minimum). Le bucket refuse tout `PutObject` chiffré avec une autre clé que `kms_key_arn`.

## Politique de la clé KMS `logs` (à fournir par EN-14)

Le module ne gère pas la clé. Sans les droits ci-dessous, l'apply échoue avec `InsufficientEncryptionPolicy` :

- CloudTrail (`cloudtrail.amazonaws.com`) : `kms:GenerateDataKey*` avec `StringLike kms:EncryptionContext:aws:cloudtrail:arn = arn:<partition>:cloudtrail:*:<account>:trail/*` et `aws:SourceArn` / `aws:SourceAccount`, plus `kms:DescribeKey`.
- CloudWatch Logs (`logs.<region>.amazonaws.com`) : `kms:Encrypt*`, `kms:Decrypt*`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`, `kms:Describe*` avec `ArnLike kms:EncryptionContext:aws:logs:arn` sur le groupe de logs du trail.
- Config : le rôle lié au service `AWSServiceRoleForConfig` avec `kms:GenerateDataKey` et `kms:Decrypt`.

## Rôle lié au service Config

`enable_config_service_linked_role` vaut `false` par défaut : le rôle n'existe qu'une fois par compte et sa création en double fait échouer l'apply. À passer à `true` dans le tfvars de l'environnement (EN-11) quand le rôle n'existe pas encore.

## Événements de données S3

`enable_cloudtrail_s3_data_events` (défaut `false`) ajoute un sélecteur d'événements avancé `AWS::S3::Object` limité aux buckets de `cloudtrail_s3_data_event_bucket_arns` (par exemple pièces jointes et state), ainsi qu'un sélecteur pour les événements de gestion, qui doivent être listés explicitement dès qu'un sélecteur avancé est utilisé.

Risque accepté lorsque le drapeau est désactivé : les accès aux objets S3 ne sont pas journalisés dans CloudTrail, donc les contrôles Security Hub FSBP S3.22 et S3.23 et CIS 3.8 et 3.9 échouent, et les lectures et écritures d'objets ne sont pas auditables. Le coût des événements de données (facturés à l'événement) justifie ce choix en dev ; à activer en prod.

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
| [aws_accessanalyzer_analyzer.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/accessanalyzer_analyzer) | resource |
| [aws_cloudtrail.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudtrail) | resource |
| [aws_cloudwatch_log_group.trail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_config_configuration_recorder.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_configuration_recorder) | resource |
| [aws_config_configuration_recorder_status.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_configuration_recorder_status) | resource |
| [aws_config_delivery_channel.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/config_delivery_channel) | resource |
| [aws_ebs_encryption_by_default.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_encryption_by_default) | resource |
| [aws_guardduty_detector.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector) | resource |
| [aws_guardduty_detector_feature.ebs_malware_protection](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector_feature) | resource |
| [aws_guardduty_detector_feature.s3_data_events](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector_feature) | resource |
| [aws_iam_account_password_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_account_password_policy) | resource |
| [aws_iam_role.trail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.trail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_service_linked_role.config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_service_linked_role) | resource |
| [aws_s3_account_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_account_public_access_block) | resource |
| [aws_s3_bucket.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_securityhub_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_account) | resource |
| [aws_securityhub_standards_subscription.fsbp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_standards_subscription) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.trail_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.trail_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_abort_incomplete_multipart_upload_days"></a> [abort\_incomplete\_multipart\_upload\_days](#input\_abort\_incomplete\_multipart\_upload\_days) | Number of days after which an incomplete multipart upload is aborted in the security log bucket. | `number` | `7` | no |
| <a name="input_cloudtrail_s3_data_event_bucket_arns"></a> [cloudtrail\_s3\_data\_event\_bucket\_arns](#input\_cloudtrail\_s3\_data\_event\_bucket\_arns) | ARNs of the S3 buckets whose object-level events are recorded (for example the attachments bucket and the state bucket). Only used when enable\_cloudtrail\_s3\_data\_events is true. | `list(string)` | `[]` | no |
| <a name="input_cloudwatch_log_retention_days"></a> [cloudwatch\_log\_retention\_days](#input\_cloudwatch\_log\_retention\_days) | Retention, in days, of the CloudTrail CloudWatch log group (dev 14, prod 90). Required when enable\_cloudtrail is true. The long-term copy of the logs lives in the log bucket (log\_bucket\_expiration\_days). | `number` | `null` | no |
| <a name="input_enable_access_analyzer"></a> [enable\_access\_analyzer](#input\_enable\_access\_analyzer) | Create the account-level IAM Access Analyzer in the current region (one account analyzer per region). | `bool` | `false` | no |
| <a name="input_enable_cloudtrail"></a> [enable\_cloudtrail](#input\_enable\_cloudtrail) | Create the multi-region CloudTrail trail (log file validation, KMS) and its CloudWatch Logs integration. Requires kms\_key\_arn, permissions\_boundary\_arn and cloudwatch\_log\_retention\_days. | `bool` | `false` | no |
| <a name="input_enable_cloudtrail_s3_data_events"></a> [enable\_cloudtrail\_s3\_data\_events](#input\_enable\_cloudtrail\_s3\_data\_events) | Record S3 object-level data events (AWS::S3::Object) of the buckets listed in cloudtrail\_s3\_data\_event\_bucket\_arns on the trail (Security Hub FSBP S3.22 and S3.23, CIS 3.8 and 3.9). Off by default: data events are billed per event. Requires enable\_cloudtrail. | `bool` | `false` | no |
| <a name="input_enable_config"></a> [enable\_config](#input\_enable\_config) | Create the AWS Config recorder and delivery channel. Delivery goes to the security log bucket, which is created when this flag or enable\_cloudtrail is true. Requires kms\_key\_arn. | `bool` | `false` | no |
| <a name="input_enable_config_service_linked_role"></a> [enable\_config\_service\_linked\_role](#input\_enable\_config\_service\_linked\_role) | Create the AWS Config service-linked role (config.amazonaws.com). Defaults to false because the role can exist only once per account and creating it twice fails the apply; set it to true in the environment tfvars (EN-11) when the role does not exist yet. The recorder always uses this role. Only used when enable\_config is true. | `bool` | `false` | no |
| <a name="input_enable_ebs_default_encryption"></a> [enable\_ebs\_default\_encryption](#input\_enable\_ebs\_default\_encryption) | Enable EBS encryption by default for the current region. | `bool` | `false` | no |
| <a name="input_enable_guardduty"></a> [enable\_guardduty](#input\_enable\_guardduty) | Create the GuardDuty detector in the current region. | `bool` | `false` | no |
| <a name="input_enable_guardduty_malware_protection"></a> [enable\_guardduty\_malware\_protection](#input\_enable\_guardduty\_malware\_protection) | Enable the GuardDuty malware protection for EBS volumes feature on the detector. Requires enable\_guardduty. Malware Protection for S3 buckets is a per-bucket plan owned by the module that owns the bucket. | `bool` | `false` | no |
| <a name="input_enable_guardduty_s3_protection"></a> [enable\_guardduty\_s3\_protection](#input\_enable\_guardduty\_s3\_protection) | Enable the GuardDuty S3 data events feature (S3 protection) on the detector. Requires enable\_guardduty. | `bool` | `false` | no |
| <a name="input_enable_iam_password_policy"></a> [enable\_iam\_password\_policy](#input\_enable\_iam\_password\_policy) | Set the account IAM password policy (14 characters minimum, all character classes, 90-day expiry, 24 passwords of history). | `bool` | `false` | no |
| <a name="input_enable_s3_account_public_access_block"></a> [enable\_s3\_account\_public\_access\_block](#input\_enable\_s3\_account\_public\_access\_block) | Enable S3 Block Public Access on the whole account (all four settings). | `bool` | `false` | no |
| <a name="input_enable_securityhub"></a> [enable\_securityhub](#input\_enable\_securityhub) | Enable Security Hub in the current region and subscribe to the AWS Foundational Security Best Practices standard. The controls need AWS Config recording to report findings. | `bool` | `false` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the logs KMS key (EN-14). It encrypts the security log bucket, the trail and the CloudTrail log group, and Config deliveries. Required when enable\_cloudtrail or enable\_config is true. Its key policy must allow cloudtrail.amazonaws.com, config.amazonaws.com (and the AWS Config service-linked role) and the CloudWatch Logs service of the region. | `string` | `null` | no |
| <a name="input_log_bucket_expiration_days"></a> [log\_bucket\_expiration\_days](#input\_log\_bucket\_expiration\_days) | Number of days after which trail and Config objects are deleted from the security log bucket. | `number` | `365` | no |
| <a name="input_log_bucket_noncurrent_version_expiration_days"></a> [log\_bucket\_noncurrent\_version\_expiration\_days](#input\_log\_bucket\_noncurrent\_version\_expiration\_days) | Number of days after which noncurrent object versions are permanently deleted from the security log bucket. | `number` | `90` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, in the form sc-<env> (for example "sc-dev"). | `string` | n/a | yes |
| <a name="input_permissions_boundary_arn"></a> [permissions\_boundary\_arn](#input\_permissions\_boundary\_arn) | ARN of the project permissions boundary attached to the IAM role created by this module (CloudTrail to CloudWatch Logs). Required when enable\_cloudtrail is true. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_analyzer_arn"></a> [access\_analyzer\_arn](#output\_access\_analyzer\_arn) | ARN of the account-level IAM Access Analyzer. Null when enable\_access\_analyzer is false. |
| <a name="output_cloudtrail_arn"></a> [cloudtrail\_arn](#output\_cloudtrail\_arn) | ARN of the multi-region trail. Null when enable\_cloudtrail is false. |
| <a name="output_cloudtrail_log_group_arn"></a> [cloudtrail\_log\_group\_arn](#output\_cloudtrail\_log\_group\_arn) | ARN of the CloudWatch log group that receives the trail events. Null when enable\_cloudtrail is false. |
| <a name="output_cloudtrail_log_group_name"></a> [cloudtrail\_log\_group\_name](#output\_cloudtrail\_log\_group\_name) | Name of the CloudWatch log group that receives the trail events (input of metric filters and alarms). Null when enable\_cloudtrail is false. |
| <a name="output_config_recorder_name"></a> [config\_recorder\_name](#output\_config\_recorder\_name) | Name of the AWS Config recorder. Null when enable\_config is false. |
| <a name="output_guardduty_detector_id"></a> [guardduty\_detector\_id](#output\_guardduty\_detector\_id) | ID of the GuardDuty detector. Null when enable\_guardduty is false. |
| <a name="output_log_bucket_arn"></a> [log\_bucket\_arn](#output\_log\_bucket\_arn) | ARN of the security log bucket. Null when neither CloudTrail nor Config is enabled. |
| <a name="output_log_bucket_name"></a> [log\_bucket\_name](#output\_log\_bucket\_name) | Name of the security log bucket. Null when neither CloudTrail nor Config is enabled. |
| <a name="output_securityhub_fsbp_standards_arn"></a> [securityhub\_fsbp\_standards\_arn](#output\_securityhub\_fsbp\_standards\_arn) | ARN of the AWS Foundational Security Best Practices standard subscribed in Security Hub. Null when enable\_securityhub is false. |
<!-- END_TF_DOCS -->

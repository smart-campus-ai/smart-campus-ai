# kms-keys

Une clé KMS gérée par le client par domaine (`data`, `logs`, `ai` par défaut), avec rotation automatique, alias `alias/<préfixe>-<domaine>` et politique de clé explicite : délégation à IAM via `:root`, administrateurs nommés, aucun principal `*`.

Les droits des services AWS (CloudWatch Logs, CloudTrail, Config, CloudFront OAC, GuardDuty Malware Protection, Bedrock, usage via DynamoDB / SQS / S3) sont désactivés par défaut et activés par des entrées, chacun avec ses conditions (contexte de chiffrement, `aws:SourceArn`, `aws:SourceAccount`, `kms:ViaService`, `kms:CallerAccount`). Une règle EventBridge optionnelle alerte (SNS) sur `ScheduleKeyDeletion` et `DisableKey`.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->

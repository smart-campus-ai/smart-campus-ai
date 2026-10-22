# notifications

Canaux de notification de la plateforme (EN-45) : deux topics SNS chiffrés par KMS (`<prefix>-admins` pour les alertes admins, `<prefix>-ops` pour les alarmes et événements SES), une ou plusieurs identités SES expéditrices (adresse e-mail et/ou domaine DKIM ; l'ADR-0003 « pas de domaine personnalisé » ne concerne que l'URL de l'application, pas l'expéditeur des e-mails) et, en option, un configuration set SES dont les événements de livraison alimentent le topic `ops`.

Points d'attention :

- **SES en sandbox** : tant que l'accès production n'est pas accordé, chaque destinataire doit être une identité vérifiée (`recipient_email_identities`, chaque propriétaire clique le lien de vérification) et le quota est de 200 messages par jour.
- Les abonnements e-mail SNS restent « en attente » jusqu'à confirmation manuelle par chaque destinataire, hors OpenTofu.
- **Identité expéditrice** : `sender_email_address` et/ou `sender_domain` (au moins un). Un domaine se vérifie en publiant les CNAME DKIM de la sortie `ses_domain_dkim_tokens` dans le DNS du propriétaire du domaine.
- **Données personnelles** : les adresses (expéditeur, destinataires, abonnements) sont des variables `sensitive`, absentes des plans. Les ressources sont indexées par un hash de l'adresse (jamais l'adresse). La valeur reste un argument de ressource, donc dans l'état, protégé par le chiffrement de l'état (KMS). Valeurs à fournir par tfvars hors dépôt public.
- **`ses:SendEmail`** est limité à l'ARN de l'identité et à `ses:FromAddress`. SES n'offre pas de clé de condition pour imposer le configuration set sur `SendEmail` : il est imposé par défaut sur l'identité (`configuration_set_name`), et l'ARN du configuration set n'est pas accordé, donc un appel qui en nomme un autre est refusé.
- **Politique des topics** : `Deny sns:*` sur le topic si `aws:SecureTransport` est faux (publication, abonnement, tags, politique de protection des données, confirmation...).
- L'ARN de l'identité e-mail et le JSON de la politique d'envoi contiennent l'adresse expéditrice : ces sorties sont `sensitive`.
- La clé KMS (EN-14) doit autoriser `kms:Decrypt` et `kms:GenerateDataKey*` aux services qui publient (CloudWatch, Budgets, SES) : cette politique de clé n'est pas gérée ici.
- Les événements SES contiennent des adresses de destinataires : limiter `configuration_set_event_types` aux problèmes de livraison.

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
| [aws_sesv2_configuration_set.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sesv2_configuration_set) | resource |
| [aws_sesv2_configuration_set_event_destination.ops](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sesv2_configuration_set_event_destination) | resource |
| [aws_sesv2_email_identity.recipient](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sesv2_email_identity) | resource |
| [aws_sesv2_email_identity.sender](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sesv2_email_identity) | resource |
| [aws_sesv2_email_identity.sender_domain](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sesv2_email_identity) | resource |
| [aws_sns_topic.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_sns_topic_subscription.email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.send_email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.topic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_admins_email_endpoints"></a> [admins\_email\_endpoints](#input\_admins\_email\_endpoints) | E-mail addresses subscribed to the admins topic (security tickets, SLA escalation). Optional. PII: sensitive. Each subscription must be confirmed manually by its owner, outside OpenTofu. | `list(string)` | `[]` | no |
| <a name="input_admins_publishers"></a> [admins\_publishers](#input\_admins\_publishers) | Who may publish to the admins topic. principal\_arns: IAM role ARNs (for example the tickets and escalation roles). services: map of AWS service principal to the aws:SourceArn patterns it may publish from (at least one, so a service is never allowed without a SourceArn condition); aws:SourceAccount is added automatically. | <pre>object({<br/>    principal_arns = optional(list(string), [])<br/>    services       = optional(map(list(string)), {})<br/>  })</pre> | `{}` | no |
| <a name="input_configuration_set_event_types"></a> [configuration\_set\_event\_types](#input\_configuration\_set\_event\_types) | SES event types published to the ops topic when enable\_configuration\_set is true. Events carry recipient addresses: keep the list to delivery problems. | `list(string)` | <pre>[<br/>  "BOUNCE",<br/>  "COMPLAINT",<br/>  "REJECT",<br/>  "RENDERING_FAILURE"<br/>]</pre> | no |
| <a name="input_enable_configuration_set"></a> [enable\_configuration\_set](#input\_enable\_configuration\_set) | Create an SES configuration set (default for the sender identity, TLS required, reputation metrics) whose bounce, complaint and reject events are published to the ops topic. | `bool` | `false` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the customer-managed KMS key (EN-14) that encrypts both SNS topics. Its key policy must let the publishing services (CloudWatch, Budgets, SES) call kms:Decrypt and kms:GenerateDataKey*. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, in the form sc-<env> (for example "sc-dev"). | `string` | n/a | yes |
| <a name="input_ops_email_endpoints"></a> [ops\_email\_endpoints](#input\_ops\_email\_endpoints) | E-mail addresses subscribed to the ops topic (alarms, budgets, SES events). Optional. PII: sensitive. Each subscription must be confirmed manually by its owner, outside OpenTofu. | `list(string)` | `[]` | no |
| <a name="input_ops_publishers"></a> [ops\_publishers](#input\_ops\_publishers) | Who may publish to the ops topic. Same shape as admins\_publishers. Typically cloudwatch.amazonaws.com (alarm ARNs of the environment) and budgets.amazonaws.com (budget ARNs). SES is added automatically for the configuration set when enable\_configuration\_set is true. | <pre>object({<br/>    principal_arns = optional(list(string), [])<br/>    services       = optional(map(list(string)), {})<br/>  })</pre> | `{}` | no |
| <a name="input_recipient_email_identities"></a> [recipient\_email\_identities](#input\_recipient\_email\_identities) | Extra e-mail addresses to verify as SES identities. Needed while the account is in the SES sandbox, where every recipient must be a verified identity. Each owner must click the verification link sent by SES. PII: sensitive. | `list(string)` | `[]` | no |
| <a name="input_sender_domain"></a> [sender\_domain](#input\_sender\_domain) | Domain to verify as an SES sender identity (DKIM), for example "mail.example.org". Optional when sender\_email\_address is set. Not the application domain (ADR-0003): it only identifies the mail sender. At least one of sender\_email\_address and sender\_domain is required. | `string` | `null` | no |
| <a name="input_sender_email_address"></a> [sender\_email\_address](#input\_sender\_email\_address) | Sender e-mail address of the SES identity (AC1: sender addresses or a domain). Optional when sender\_domain is set. PII: sensitive; provide it through a tfvars file kept out of the public repository, it is never hardcoded in the module. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_admins_topic_arn"></a> [admins\_topic\_arn](#output\_admins\_topic\_arn) | ARN of the admins SNS topic (security tickets, SLA escalation). The tickets and escalation roles get sns:Publish on this ARN only. |
| <a name="output_configuration_set_arn"></a> [configuration\_set\_arn](#output\_configuration\_set\_arn) | ARN of the SES configuration set, or null when enable\_configuration\_set is false. |
| <a name="output_ops_topic_arn"></a> [ops\_topic\_arn](#output\_ops\_topic\_arn) | ARN of the ops SNS topic (CloudWatch alarms, budgets, SES delivery events). |
| <a name="output_send_email_policy_json"></a> [send\_email\_policy\_json](#output\_send\_email\_policy\_json) | IAM policy document (JSON) granting ses:SendEmail on the sender identity ARN(s) with the ses:FromAddress condition, to attach to the notifier role. Sensitive: it contains the sender e-mail address. |
| <a name="output_ses_domain_dkim_tokens"></a> [ses\_domain\_dkim\_tokens](#output\_ses\_domain\_dkim\_tokens) | DKIM tokens of the sender domain: publish <token>._domainkey.<domain> CNAME records pointing to <token>.dkim.amazonses.com to verify the domain. Empty when sender\_domain is not set. |
| <a name="output_ses_domain_identity_arn"></a> [ses\_domain\_identity\_arn](#output\_ses\_domain\_identity\_arn) | ARN of the SES sender domain identity, or null when sender\_domain is not set. |
| <a name="output_ses_identity_arn"></a> [ses\_identity\_arn](#output\_ses\_identity\_arn) | ARN of the SES sender e-mail identity, or null when only sender\_domain is set. Sensitive: the ARN contains the sender e-mail address. |
<!-- END_TF_DOCS -->

# budget

Budget AWS mensuel (type `COST`, en USD) avec alertes sur le coût prévisionnel (80 % et 100 %) et réel (100 %) vers un topic SNS et/ou des adresses email, filtre optionnel sur le tag de coût `Project`, et détection d'anomalies de coût optionnelle (Cost Anomaly Detection).

Le topic SNS appartient au module notifications : ce module expose `topic_policy_statement_json`, le statement à fusionner dans la policy du topic pour autoriser `budgets.amazonaws.com` et `costalerts.amazonaws.com` à publier (condition `aws:SourceAccount`).

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
| [aws_budgets_budget.monthly](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget) | resource |
| [aws_ce_anomaly_monitor.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_anomaly_monitor) | resource |
| [aws_ce_anomaly_subscription.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_anomaly_subscription) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.topic_publish](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_actual_thresholds_percent"></a> [actual\_thresholds\_percent](#input\_actual\_thresholds\_percent) | Percentages of the monthly limit above which a notification is sent on the actual cost. | `list(number)` | <pre>[<br/>  100<br/>]</pre> | no |
| <a name="input_anomaly_threshold_usd"></a> [anomaly\_threshold\_usd](#input\_anomaly\_threshold\_usd) | Minimum absolute total impact, in USD, of an anomaly for an alert to be sent. | `number` | `10` | no |
| <a name="input_enable_anomaly_detection"></a> [enable\_anomaly\_detection](#input\_enable\_anomaly\_detection) | Create a Cost Anomaly Detection monitor (per AWS service) and a subscription that publishes to sns\_topic\_arn. | `bool` | `false` | no |
| <a name="input_forecasted_thresholds_percent"></a> [forecasted\_thresholds\_percent](#input\_forecasted\_thresholds\_percent) | Percentages of the monthly limit above which a notification is sent on the forecasted cost. | `list(number)` | <pre>[<br/>  80,<br/>  100<br/>]</pre> | no |
| <a name="input_monthly_limit_usd"></a> [monthly\_limit\_usd](#input\_monthly\_limit\_usd) | Monthly cost limit of the budget, in USD. | `number` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, for example "sc-dev". | `string` | n/a | yes |
| <a name="input_notification_emails"></a> [notification\_emails](#input\_notification\_emails) | Email addresses that receive the budget notifications directly (max 10 per notification). | `list(string)` | `[]` | no |
| <a name="input_project_tag_key"></a> [project\_tag\_key](#input\_project\_tag\_key) | Key of the cost allocation tag used to filter the budget when project\_tag\_value is set. | `string` | `"Project"` | no |
| <a name="input_project_tag_value"></a> [project\_tag\_value](#input\_project\_tag\_value) | Value of the cost allocation tag project\_tag\_key used to filter the budget. When null, the budget covers the whole account. The tag must be activated as a cost allocation tag in the billing console. | `string` | `null` | no |
| <a name="input_sns_topic_arn"></a> [sns\_topic\_arn](#input\_sns\_topic\_arn) | ARN of the SNS topic (owned by the notifications module) that receives the budget and anomaly alerts. The topic policy must allow budgets.amazonaws.com and costalerts.amazonaws.com to publish: see the topic\_policy\_statement\_json output. Required when enable\_anomaly\_detection is true. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_anomaly_monitor_arn"></a> [anomaly\_monitor\_arn](#output\_anomaly\_monitor\_arn) | ARN of the Cost Anomaly Detection monitor, null when enable\_anomaly\_detection is false. |
| <a name="output_anomaly_subscription_arn"></a> [anomaly\_subscription\_arn](#output\_anomaly\_subscription\_arn) | ARN of the Cost Anomaly Detection subscription, null when enable\_anomaly\_detection is false. |
| <a name="output_budget_arn"></a> [budget\_arn](#output\_budget\_arn) | ARN of the monthly cost budget. |
| <a name="output_budget_name"></a> [budget\_name](#output\_budget\_name) | Name of the monthly cost budget. |
| <a name="output_topic_policy_statement_json"></a> [topic\_policy\_statement\_json](#output\_topic\_policy\_statement\_json) | IAM policy document (JSON) with the statement allowing budgets.amazonaws.com and costalerts.amazonaws.com to publish to sns\_topic\_arn (conditioned on aws:SourceAccount). To be merged into the topic policy by the notifications module. Null when sns\_topic\_arn is null. |
<!-- END_TF_DOCS -->

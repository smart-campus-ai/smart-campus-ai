# observability

Tableau de bord CloudWatch, alarmes vers le topic SNS ops (EN-45) et filtres de métriques sur les logs (EN-61).

Le module reçoit uniquement des noms (API et stage, fonctions Lambda, tables DynamoDB, web ACL, DLQ, groupes de logs) et n'en découvre aucun. Il ne crée aucun groupe de logs : ils appartiennent aux producteurs (`lambda-service`, stage API, journalisation WAF) et sont chiffrés par la clé KMS `logs` (EN-14) avec leur rétention. Aucun export ni abonnement de logs.

## Mapping des critères d'acceptation EN-61 aux modules propriétaires

| Critère | Responsabilité | Module propriétaire | Test |
|---------|----------------|---------------------|------|
| **AC1** — Groupes de logs Lambda/API/WAF explicites, chiffrés CMK, rétention définie, logs structurés | Producteur | `lambda-service` (log groups Lambda), `rest-api` (log group API), `edge` (log group WAF) | Tests unitaires des modules producteurs |
| **AC2** — Tracing X-Ray actif sur API Gateway et Lambda | Producteur | `rest-api` (`tracing_enabled = true`), `lambda-service` (`tracing_config { mode = "Active" }`) | Tests unitaires des modules producteurs + test d'intégration platform |
| **AC6** — Logs d'accès API sans Authorization ni corps de requête | Producteur | `rest-api` (format JSON dans `access_log_settings`) | Test unitaire du module `rest-api` |
| **AC3** — Dashboard avec widgets requis | Ce module | `observability` | `en61_ac3_*` |
| **AC4** — Filtre 401/403 + alarme | Ce module | `observability` | `en61_ac4_*` |
| **AC5** — Alarmes 5xx, latence, Lambda, DLQ, WAF | Ce module | `observability` | `en61_ac5_*` |

Les AC1, AC2 et AC6 relèvent des modules producteurs : ce module ne fait qu'attacher des filtres aux groupes de logs existants. La stack `platform` orchestre la composition et doit inclure un test d'intégration vérifiant le chaînage X-Ray API→Lambda.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.13.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Provider Aliases

The module requires a `us-east-1` provider alias for CloudFront-scope WAF alarms. In the calling stack:

```hcl
provider "aws" {
  region = "us-east-1"
  alias  = "us_east_1"
}

module "observability" {
  source = "../modules/observability"
  # ...
}
```

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.70.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_dashboard.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard) | resource |
| [aws_cloudwatch_log_metric_filter.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_metric_filter) | resource |
| [aws_cloudwatch_metric_alarm.api_5xx_rate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.api_latency_p95](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.dlq_depth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.lambda_errors](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.lambda_throttles](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.log_metric_filter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.waf_blocked_requests](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.cloudfront_waf_blocked_requests](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alarm_datapoints_to_alarm"></a> [alarm\_datapoints\_to\_alarm](#input\_alarm\_datapoints\_to\_alarm) | Number of breaching periods, out of alarm\_evaluation\_periods, that put a rate-based alarm into ALARM. | `number` | `2` | no |
| <a name="input_alarm_evaluation_periods"></a> [alarm\_evaluation\_periods](#input\_alarm\_evaluation\_periods) | Number of periods evaluated by the rate-based alarms (API 5xx rate, API latency p95, WAF blocks, log metric filters). Errors, throttles and DLQ depth alarms always evaluate one period. | `number` | `3` | no |
| <a name="input_alarm_period_seconds"></a> [alarm\_period\_seconds](#input\_alarm\_period\_seconds) | Evaluation period of every alarm, in seconds. A multiple of 60; keep 300 or more for SQS and DynamoDB metrics, which are published every 5 minutes. | `number` | `300` | no |
| <a name="input_alarm_topic_arn"></a> [alarm\_topic\_arn](#input\_alarm\_topic\_arn) | ARN of the SNS topic ("ops" topic, EN-45) notified when an alarm goes into the ALARM state. The topic policy must allow cloudwatch.amazonaws.com to publish, scoped by aws:SourceAccount. | `string` | n/a | yes |
| <a name="input_api"></a> [api](#input\_api) | REST API stage to observe (API Gateway ApiName and Stage dimensions). Null disables the API widgets and the API 5xx and latency alarms. | <pre>object({<br/>    name       = string<br/>    stage_name = string<br/>  })</pre> | `null` | no |
| <a name="input_api_5xx_min_requests"></a> [api\_5xx\_min\_requests](#input\_api\_5xx\_min\_requests) | Minimum number of requests in a period for the 5xx rate to be evaluated; below it the rate is treated as 0 so that a single error on a quiet API does not page. | `number` | `10` | no |
| <a name="input_api_5xx_rate_threshold_percent"></a> [api\_5xx\_rate\_threshold\_percent](#input\_api\_5xx\_rate\_threshold\_percent) | API 5xx rate (percent of requests) above which the 5xx alarm fires. | `number` | `1` | no |
| <a name="input_api_latency_p95_threshold_ms"></a> [api\_latency\_p95\_threshold\_ms](#input\_api\_latency\_p95\_threshold\_ms) | API p95 latency, in milliseconds, above which the latency alarm fires (NFR: 2000). | `number` | `2000` | no |
| <a name="input_auth_failure_filter_pattern"></a> [auth\_failure\_filter\_pattern](#input\_auth\_failure\_filter\_pattern) | CloudWatch Logs filter pattern counting authentication failures in the access log group. The default matches a JSON access log with a numeric status field; align it with the access log format defined by EN-33. | `string` | `"{ ($.status = 401) || ($.status = 403) }"` | no |
| <a name="input_auth_failure_log_group_name"></a> [auth\_failure\_log\_group\_name](#input\_auth\_failure\_log\_group\_name) | Name of the API access log group (EN-33) holding JSON access logs. When set, a metric filter counts 401/403 responses, with a dashboard widget and an alarm. Null disables it. | `string` | `null` | no |
| <a name="input_auth_failure_threshold"></a> [auth\_failure\_threshold](#input\_auth\_failure\_threshold) | Number of 401/403 responses per period at or above which the authentication failure alarm fires (spike detection). | `number` | `50` | no |
| <a name="input_cloudfront_waf_web_acl_names"></a> [cloudfront\_waf\_web\_acl\_names](#input\_cloudfront\_waf\_web\_acl\_names) | Names of the CLOUDFRONT-scope web ACLs to observe. Their metrics live in us-east-1 with the 'Global' region dimension. Each one gets a blocked-requests alarm. | `set(string)` | `[]` | no |
| <a name="input_dlq_depth_threshold"></a> [dlq\_depth\_threshold](#input\_dlq\_depth\_threshold) | Number of visible messages above which a DLQ depth alarm fires. 0 means any message. | `number` | `0` | no |
| <a name="input_dlq_queue_names"></a> [dlq\_queue\_names](#input\_dlq\_queue\_names) | Names of the SQS dead-letter queues to observe. Each one gets a depth alarm. | `set(string)` | `[]` | no |
| <a name="input_dynamodb_table_names"></a> [dynamodb\_table\_names](#input\_dynamodb\_table\_names) | Names of the DynamoDB tables to show on the dashboard (consumed capacity and throttle events). No alarm. | `set(string)` | `[]` | no |
| <a name="input_lambda_errors_threshold"></a> [lambda\_errors\_threshold](#input\_lambda\_errors\_threshold) | Number of errors per period above which a Lambda errors alarm fires. | `number` | `0` | no |
| <a name="input_lambda_function_names"></a> [lambda\_function\_names](#input\_lambda\_function\_names) | Names of the Lambda functions to observe. Each one gets an errors alarm and a throttles alarm. | `set(string)` | `[]` | no |
| <a name="input_lambda_throttles_threshold"></a> [lambda\_throttles\_threshold](#input\_lambda\_throttles\_threshold) | Number of throttles per period above which a Lambda throttles alarm fires. | `number` | `0` | no |
| <a name="input_log_metric_filters"></a> [log\_metric\_filters](#input\_log\_metric\_filters) | Extra metric filters, keyed by a stable name (metric name and alarm suffix). Each filter counts matching events (value 1, no extracted field, so no log content reaches metrics). An alarm is created when alarm\_threshold is set: it fires when the count over alarm\_period\_seconds reaches the threshold. | <pre>map(object({<br/>    log_group_name  = string<br/>    pattern         = string<br/>    alarm_threshold = optional(number)<br/>  }))</pre> | `{}` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, in the form sc-<env> (for example "sc-dev"). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_waf_blocked_requests_threshold"></a> [waf\_blocked\_requests\_threshold](#input\_waf\_blocked\_requests\_threshold) | Number of requests blocked by a regional web ACL per period above which the WAF alarm fires (spike detection). | `number` | `100` | no |
| <a name="input_waf_regional_web_acl_names"></a> [waf\_regional\_web\_acl\_names](#input\_waf\_regional\_web\_acl\_names) | Names of the REGIONAL web ACLs (API stage) to observe, in the region of the module. Each one gets a blocked-requests alarm. | `set(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alarm_arns"></a> [alarm\_arns](#output\_alarm\_arns) | ARNs of every alarm created by the module, keyed by alarm name. |
| <a name="output_dashboard_arn"></a> [dashboard\_arn](#output\_dashboard\_arn) | ARN of the CloudWatch dashboard. |
| <a name="output_dashboard_name"></a> [dashboard\_name](#output\_dashboard\_name) | Name of the CloudWatch dashboard. |
| <a name="output_metric_filter_names"></a> [metric\_filter\_names](#output\_metric\_filter\_names) | Names of the log metric filters, keyed by filter key (auth-failures for the authentication failure filter). |
| <a name="output_metric_namespace"></a> [metric\_namespace](#output\_metric\_namespace) | CloudWatch namespace of the custom metrics produced by the log metric filters. |
<!-- END_TF_DOCS -->

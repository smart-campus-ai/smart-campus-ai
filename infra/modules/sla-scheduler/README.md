# sla-scheduler

Infrastructure du Scheduler SLA (RF01, ADR-0008) : groupe de schedules `<prefix>-sla`, rôle d'exécution du Scheduler limité à l'invocation de l'alias `live` de `escalation`, et DLQ SQS chiffrée (KMS) optionnelle pour les échecs de la cible.

Les schedules eux-mêmes (`at(created+24h)`, `ActionAfterCompletion=DELETE`) sont créés à l'exécution par la fonction `tickets`. La sortie `tickets_schedules_policy_json` donne les droits correspondants (`scheduler:CreateSchedule`/`DeleteSchedule` sur le groupe SLA, `iam:PassRole` sur le rôle d'exécution uniquement) à attacher au rôle de `tickets`.

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
| [aws_iam_role.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_scheduler_schedule_group.sla](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule_group) | resource |
| [aws_sqs_queue.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_policy.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.tickets_schedules](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_dlq_kms_key_arn"></a> [dlq\_kms\_key\_arn](#input\_dlq\_kms\_key\_arn) | ARN of the customer-managed KMS key (EN-14) that encrypts the dead-letter queue. Required when enable\_dlq is true, must be null otherwise. | `string` | `null` | no |
| <a name="input_dlq_message_retention_seconds"></a> [dlq\_message\_retention\_seconds](#input\_dlq\_message\_retention\_seconds) | How long the dead-letter queue keeps a failed event, in seconds (60 to 1209600, that is 14 days). Events only carry a ticket identifier. | `number` | `1209600` | no |
| <a name="input_enable_dlq"></a> [enable\_dlq](#input\_enable\_dlq) | Create the SQS dead-letter queue that receives the events of schedules whose target invocation failed after all retries (AC4). Schedules reference it through the dlq\_arn output. | `bool` | `true` | no |
| <a name="input_escalation_alias_arn"></a> [escalation\_alias\_arn](#input\_escalation\_alias\_arn) | ARN of the "live" alias of the escalation Lambda function (arn:<partition>:lambda:<region>:<account id>:function:<name>:live). The scheduler execution role may invoke this ARN only, never the unqualified function or $LATEST. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Environment prefix of every resource name (sc-<env>, for example "sc-dev"). The schedule group is named <name\_prefix>-sla. | `string` | n/a | yes |
| <a name="input_permissions_boundary_arn"></a> [permissions\_boundary\_arn](#input\_permissions\_boundary\_arn) | ARN of the project permissions boundary policy attached to the scheduler execution role. null attaches no boundary: only for the workshop exception of ADR-0014 (stacks enforce its scope and expiry). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_dlq_arn"></a> [dlq\_arn](#output\_dlq\_arn) | ARN of the encrypted dead-letter queue, to set as the dead\_letter\_config of each schedule target. Null when enable\_dlq is false. |
| <a name="output_dlq_name"></a> [dlq\_name](#output\_dlq\_name) | Name of the dead-letter queue, for alarms on its depth. Null when enable\_dlq is false. |
| <a name="output_schedule_group_arn"></a> [schedule\_group\_arn](#output\_schedule\_group\_arn) | ARN of the SLA schedule group. |
| <a name="output_schedule_group_name"></a> [schedule\_group\_name](#output\_schedule\_group\_name) | Name of the SLA schedule group (<name\_prefix>-sla), passed as GroupName when tickets creates a schedule. |
| <a name="output_scheduler_role_arn"></a> [scheduler\_role\_arn](#output\_scheduler\_role\_arn) | ARN of the scheduler execution role, passed as the target RoleArn of each schedule. tickets may pass this role and no other (iam:PassRole). |
| <a name="output_scheduler_role_name"></a> [scheduler\_role\_name](#output\_scheduler\_role\_name) | Name of the scheduler execution role. |
| <a name="output_tickets_schedules_policy_json"></a> [tickets\_schedules\_policy\_json](#output\_tickets\_schedules\_policy\_json) | IAM policy document (JSON) for the tickets function role: scheduler:CreateSchedule and scheduler:DeleteSchedule on the SLA group schedules only, and iam:PassRole on the scheduler execution role only, to the scheduler service. Attach it to the tickets role as an extra policy. |
<!-- END_TF_DOCS -->

# bedrock-guardrail

Guardrail Bedrock de l'assistant (EN-52, RF03, US08) : sujets interdits, filtres de contenu, filtre d'attaque par prompt (entrées, sensibilité HIGH), masquage ou blocage des PII, liste de gros mots gérée, vérification d'ancrage contextuel et de pertinence avec seuils paramétrables. Chiffré par la clé KMS `ai` (EN-14).

Chaque modification du Guardrail publie une nouvelle version immuable. La sortie `guardrail_version` est passée à la fonction `chat` par variable d'environnement, avec `guardrail_id`.

Les messages de blocage sont en français et proposent la création d'un ticket.

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
| [aws_bedrock_guardrail.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrock_guardrail) | resource |
| [aws_bedrock_guardrail_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/bedrock_guardrail_version) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_blocked_input_message"></a> [blocked\_input\_message](#input\_blocked\_input\_message) | Message returned when a prompt is blocked. In French, it says the assistant does not know and offers to create a ticket (EN-52-AC5). | `string` | `"Je ne sais pas répondre à cette demande. Souhaitez-vous créer un ticket pour qu'un agent vous aide ?"` | no |
| <a name="input_blocked_output_message"></a> [blocked\_output\_message](#input\_blocked\_output\_message) | Message returned when an answer is blocked (denied topic, PII, grounding below threshold). In French, it says the assistant does not know and offers to create a ticket (EN-52-AC5). | `string` | `"Je ne sais pas répondre de façon fiable à cette question. Souhaitez-vous créer un ticket pour qu'un agent vous réponde ?"` | no |
| <a name="input_content_filter_strength"></a> [content\_filter\_strength](#input\_content\_filter\_strength) | Strength of the HATE, INSULTS, SEXUAL, VIOLENCE and MISCONDUCT filters, applied to prompts and answers. The PROMPT\_ATTACK filter is always HIGH on inputs. | `string` | `"HIGH"` | no |
| <a name="input_denied_topics"></a> [denied\_topics](#input\_denied\_topics) | Topics the assistant must refuse, keyed by topic name (letters, digits, spaces and \_ - ! ? . only, 100 characters max). Each topic has a definition (200 characters max) and up to 5 example phrases (100 characters max each). At least one topic is required. | <pre>map(object({<br/>    definition = string<br/>    examples   = optional(list(string), [])<br/>  }))</pre> | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (for example "dev" or "prod"), applied as the Environment tag. | `string` | n/a | yes |
| <a name="input_grounding_threshold"></a> [grounding\_threshold](#input\_grounding\_threshold) | Contextual grounding threshold: minimum confidence that an answer is grounded in the retrieved sources. Below it, the answer is blocked (RF03). Between 0 and 0.99, the range accepted by Bedrock. | `number` | `0.75` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the customer-managed KMS key ("ai" domain, EN-14) that encrypts the guardrail. The key policy must allow the principal applying the module and the Bedrock service to use it. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, in the form sc-<env> (for example "sc-dev"). | `string` | n/a | yes |
| <a name="input_pii_entities_anonymize"></a> [pii\_entities\_anonymize](#input\_pii\_entities\_anonymize) | PII types replaced by a placeholder (ANONYMIZE) in prompts and answers. Together with pii\_entities\_block it must cover at least EMAIL, PHONE and NAME (EN-52-AC2). | `set(string)` | <pre>[<br/>  "NAME",<br/>  "EMAIL",<br/>  "PHONE",<br/>  "ADDRESS",<br/>  "AGE",<br/>  "USERNAME",<br/>  "IP_ADDRESS"<br/>]</pre> | no |
| <a name="input_pii_entities_block"></a> [pii\_entities\_block](#input\_pii\_entities\_block) | PII types for which the whole prompt or answer is blocked (BLOCK). Must not overlap with pii\_entities\_anonymize (checked by a precondition on the guardrail, not a variable validation, to avoid a validation cycle). | `set(string)` | <pre>[<br/>  "CREDIT_DEBIT_CARD_NUMBER",<br/>  "CREDIT_DEBIT_CARD_CVV",<br/>  "CREDIT_DEBIT_CARD_EXPIRY",<br/>  "PASSWORD",<br/>  "PIN",<br/>  "INTERNATIONAL_BANK_ACCOUNT_NUMBER",<br/>  "AWS_ACCESS_KEY",<br/>  "AWS_SECRET_KEY"<br/>]</pre> | no |
| <a name="input_relevance_threshold"></a> [relevance\_threshold](#input\_relevance\_threshold) | Contextual relevance threshold: minimum confidence that an answer is relevant to the question. Below it, the answer is blocked (RF03). Between 0 and 0.99, the range accepted by Bedrock. | `number` | `0.5` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to the guardrail, merged with the provider default\_tags. The Environment tag is always set from var.environment. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_guardrail_arn"></a> [guardrail\_arn](#output\_guardrail\_arn) | ARN of the guardrail, scoped in the bedrock:ApplyGuardrail / bedrock:InvokeModel permissions of the chat function. |
| <a name="output_guardrail_id"></a> [guardrail\_id](#output\_guardrail\_id) | ID of the guardrail. Pair it with guardrail\_version in the Bedrock calls (guardrailIdentifier). |
| <a name="output_guardrail_version"></a> [guardrail\_version](#output\_guardrail\_version) | Published (immutable) version of the guardrail, passed to the chat function as guardrailVersion. |
<!-- END_TF_DOCS -->

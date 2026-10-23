# Stack platform

Compose les briques de la plateforme pour un environnement (`dev` ou `prod`) : identité, edge, API, données, calcul, IA et notifications. Un state par environnement (`<env>/platform.tfstate`). Aucun `apply` local : le déploiement passe par la CI (ADR-0009).

```
tofu -chdir=infra/stacks/platform init -backend-config=../../envs/<env>/backend.hcl -backend-config="key=<env>/platform.tfstate"
tofu -chdir=infra/stacks/platform plan -var-file=../../envs/<env>/platform.tfvars
```

## Contrat avec la stack foundation (SSM, pas de `terraform_remote_state`)

La stack lit les ARN des clés KMS publiés par `foundation` comme paramètres `String` :

| Paramètre | Usage |
| --- | --- |
| `/smartcampus/<env>/foundation/kms/data/arn` | tables, buckets de données, SNS, SQS, variables d'environnement Lambda |
| `/smartcampus/<env>/foundation/kms/logs/arn` | log groups des fonctions et de l'API |
| `/smartcampus/<env>/foundation/kms/ai/arn` | guardrail, Knowledge Base, S3 Vectors |

Elle publie en retour, sous `/smartcampus/<env>/platform/` (fichier `ssm.tf`, type `String`, aucun secret) :

| Clé | Valeur |
| --- | --- |
| `api/invoke_url` | URL d'invocation du stage de l'API |
| `site/url`, `site/bucket_name`, `site/distribution_id` | URL CloudFront, bucket de la SPA, distribution à invalider |
| `identity/user_pool_id`, `identity/client_id`, `identity/hosted_ui_base_url` | configuration de la SPA |
| `lambda/<fonction>/name` | nom déployé de chacune des huit fonctions (`tickets`, `kpi`, `chat`, `escalation`, `notifier`, `kb-sync`, `kpi-aggregator`, `pre-token`) |
| `kb/knowledge_base_id`, `kb/data_source_id`, `kb/source_bucket_name` | seulement si `enable_knowledge_base` |

Les mêmes valeurs sont des `output` de la stack.

Politique de clé à prévoir côté foundation : la clé `data` doit laisser `cloudfront.amazonaws.com` lire le bucket de la SPA (condition `aws:SourceArn` sur la distribution, sortie `site_distribution_arn`, connue seulement après le premier apply de cette stack) et laisser les services S3, SNS, SQS et DynamoDB l'utiliser. La clé `logs` doit autoriser CloudWatch Logs.

## Variables passées par l'environnement

Non stockées dans les `tfvars` : `TF_VAR_state_kms_key_arn`, `TF_VAR_permissions_boundary_arn`, `TF_VAR_sender_email_address` (ou `sender_domain` + `sender_local_parts`), et, si besoin, `TF_VAR_recipient_email_identities`, `TF_VAR_admins_email_endpoints`, `TF_VAR_ops_email_endpoints` (données personnelles, `sensitive`).

## Permissions boundary et issue #98

`permissions_boundary_arn` est obligatoire et non nullable : `lambda-service`, `sla-scheduler` et `knowledge-base` refusent une boundary `null` (seul `attachments-bucket` l'accepte, et seulement sans analyse de malware). Tant que le rôle de l'atelier ne peut pas poser de boundary (issue #98), l'apply de cette stack est bloqué ; le plan et la validation restent possibles.

## Choix de composition

- **Pas de cycle de ressources malgré des modules qui se référencent.** L'identité a besoin de l'URL du site (callback), le site de l'origine API, l'API de l'ARN du user pool (authorizer). Dans le module `identity`, seul le client d'application lit les URL de callback, pas le user pool ; la chaîne se résout donc ressource par ressource. Le domaine hébergé Cognito (CSP du site) est construit depuis son préfixe pour la même raison. De même, le topic `admins` dépend des rôles de `tickets` et `escalation`, jamais l'inverse.
- **`tickets` : la politique du Scheduler est attachée dans la stack** (`aws_iam_role_policy.tickets_schedules`, `iam.tf`) et non par `extra_policy_json`, car `lambda-service` refuse `iam:PassRole` par conception. Le document vient du module `sla-scheduler` : `PassRole` sur le seul rôle d'exécution du Scheduler, vers `scheduler.amazonaws.com`, et `CreateSchedule`/`DeleteSchedule` sur le seul groupe SLA. La boundary de l'environnement doit autoriser ces actions.
- **`kb-sync` lit les identifiants de la Knowledge Base dans SSM à l'exécution** (`KNOWLEDGE_BASE_ID_SSM_PARAMETER`, `DATA_SOURCE_ID_SSM_PARAMETER`). La Knowledge Base dépend de l'alias `kb-sync` (notification S3) : si `kb-sync` dépendait d'elle, l'ordre serait inversé et le premier apply échouerait. Pour la même raison, sa politique d'ingestion est attachée dans la stack (`aws_iam_role_policy.kb_sync_ingestion`).
- **OpenAPI** : `packages/contracts` n'existe pas encore (EN-05). `openapi/openapi.json.tftpl` est un contrat minimal (tickets, kpi, chat) avec l'authorizer Cognito sans scope (jeton d'identité) en attendant EN-32. Le `check "api_routes_match_openapi"` compare ses routes à `local.api_routes`, qui alimentent les permissions d'invocation.
- **Pas de domaine personnalisé** (ADR-0003) : l'application et l'API sont servies par l'URL `*.cloudfront.net`.

## Variables d'environnement des fonctions (contrat provisoire, à reprendre dans EN-05)

| Fonction | Variables |
| --- | --- |
| `tickets` | `TICKETS_TABLE`, `TICKETS_OWNER_INDEX`, `TICKETS_STATUS_INDEX`, `ATTACHMENTS_BUCKET`, `ATTACHMENTS_PREFIX`, `ATTACHMENTS_MAX_BYTES`, `ATTACHMENTS_CONTENT_TYPES`, `ADMINS_TOPIC_ARN`, `SLA_SCHEDULE_GROUP`, `SLA_SCHEDULER_ROLE_ARN`, `SLA_TARGET_ARN`, `SLA_DLQ_ARN` |
| `chat` | `CHAT_SESSIONS_TABLE`, `CHAT_SESSIONS_OWNER_INDEX`, `CHAT_SESSIONS_TTL_ATTRIBUTE`, `CHAT_RETENTION_DAYS`, `GUARDRAIL_ID`, `GUARDRAIL_VERSION`, et avec la Knowledge Base `KNOWLEDGE_BASE_ID`, `CHAT_MODEL_ID` |
| `escalation` | `TICKETS_TABLE`, `ADMINS_TOPIC_ARN` |
| `kb-sync` | `KNOWLEDGE_BASE_ID_SSM_PARAMETER`, `DATA_SOURCE_ID_SSM_PARAMETER` |
| `kpi`, `notifier`, `kpi-aggregator`, `pre-token` | aucune pour l'instant |

## Reste à câbler (TODO dans le code)

- **WAF** (PR #106) : `web_acl_id` de `static-site` (`edge.tf`) et `web_acl_arn` de `rest-api` (`api.tf`).
- **Modules kpi, observability, budget, security-baseline** : table `kpi`, droits de `kpi` et `kpi-aggregator`, `ops_publishers` des topics, journaux de CloudFront.
- **Mappings de stream** du `notifier` et du `kpi-aggregator` (filtres, échecs partiels, destination SQS) : les filtres dépendent du contrat de SE.
- **`notifier`** : adresse d'expéditeur (donnée personnelle) à lire dans SSM à l'exécution.
- **`pre-token`** : le module `identity` n'a pas d'entrée pour le trigger Lambda (US06).
- **Utilisateurs de test** Cognito et fédération Entra ID (US06).

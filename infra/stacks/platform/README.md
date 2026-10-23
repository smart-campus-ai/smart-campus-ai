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

Une `postcondition` sur chaque `data "aws_ssm_parameter" "kms"` (`main.tf`) vérifie que l'ARN lu est une clé du compte, de la région et de la partition courants (`^arn:<partition>:kms:<région>:<compte>:key/<id>$`) ; sinon le plan échoue, avant toute utilisation de la valeur.

Politique de clé à prévoir côté foundation : la clé `data` doit laisser `cloudfront.amazonaws.com` lire le bucket de la SPA (condition `aws:SourceArn` sur la distribution, sortie `site_distribution_arn`, connue seulement après le premier apply de cette stack) et laisser les services S3, SNS, SQS et DynamoDB l'utiliser. La clé `logs` doit autoriser CloudWatch Logs.

## Variables passées par l'environnement

Non stockées dans les `tfvars` : `TF_VAR_state_kms_key_arn`, `TF_VAR_permissions_boundary_arn`, `TF_VAR_sender_email_address` (ou `sender_domain` + `sender_local_parts`), et, si besoin, `TF_VAR_recipient_email_identities`, `TF_VAR_admins_email_endpoints`, `TF_VAR_ops_email_endpoints` (données personnelles, `sensitive`).

`TF_VAR_sender_email_address` est exigée de la CI (variable ou secret GitHub de l'environnement) tant que `sender_domain` n'est pas utilisé : le module `notifications` refuse un plan sans identité d'expéditeur. L'adresse est une donnée personnelle, donc jamais dans un `tfvars` ni dans une sortie ; le `notifier` la lit dans SSM à l'exécution.

## Drapeaux et réglages d'environnement (`envs/<env>/platform.tfvars`)

| Variable | dev | prod | Rôle |
| --- | --- | --- | --- |
| `enable_waf` | `true` | `true` (imposé par une validation) | web ACL CLOUDFRONT sur la distribution et REGIONAL sur le stage de l'API (RF04) |
| `waf_rate_limit_per_ip` | 1000 | 2000 | requêtes par IP et par fenêtre de 300 s (NAT de campus partagé) |
| `waf_rate_limit_per_authorization` | 500 | 1000 | requêtes par utilisateur (en-tête `Authorization`), ACL régionale seulement |
| `enable_malware_protection` | `false` | `true` (imposé par une validation) | GuardDuty Malware Protection for S3 : sans lui, les pièces jointes sont servies sans analyse. Prod n'est pas déployé pendant l'atelier (ADR-0002) ; confirmer la disponibilité du service (EN-11) avant le premier apply de prod |
| `enable_knowledge_base` | `false` | `false` | service non confirmé dans le compte (EN-11) |

## WAF (RF04)

- `waf.tf` instancie le module `waf` deux fois. La portée `CLOUDFRONT` utilise `providers = { aws = aws.us_east_1 }` et son ARN alimente `web_acl_id` de `static-site`. La portée `REGIONAL` est associée au stage de l'API par `associated_resource_arns = { api = module.rest_api.stage_arn }`. L'entrée `web_acl_arn` de `rest-api` reste `null` : la renseigner aussi créerait deux fois la même association.
- Les journaux (`aws-waf-logs-<prefix>-<portée>`) sont chiffrés par la clé `logs` de `foundation`, lue dans SSM. Le groupe de la portée `CLOUDFRONT` est en `us-east-1` : la clé `logs` doit y être aussi (toujours vrai tant que `aws_region` est `us-east-1`). Un `check` le signale sinon.
- La règle par IP de l'ACL régionale voit l'adresse du point de présence CloudFront pour le trafic qui passe par `/api/*`, pas celle du visiteur ; seule la règle par `Authorization` y est discriminante. À traiter avec les tests de charge (EN-84).

## Table KPI

`module.kpi_store` (module `kpi`) crée la table des agrégats, la file d'échec SQS et le mapping stream `tickets` → alias `live` de `kpi-aggregator` (filtres, échecs partiels par élément, bissection, destination d'échec). Sa politique d'accès est attachée au rôle de la fonction dans `iam.tf` (`aws_iam_role_policy_attachment.kpi_aggregator`) ; la fonction `kpi` reçoit une lecture seule (`BatchGetItem`, `GetItem`, `Query`) sur cette table. Le contrat du handler (idempotence, comparaison des statuts) est décrit dans le README du module.

Ordre de création : un `depends_on` sur le module `kpi` serait un cycle (l'attachement lit l'ARN de la politique publiée par ce module). Le module reçoit donc `function_name` par `terraform_data.kpi_aggregator_iam_ready` (`iam.tf`), qui attend l'attachement : seul le mapping lit cette entrée, il est créé après l'IAM et un seul apply suffit. La propagation IAM reste éventuellement cohérente ; en cas d'échec rare du mapping, relancer l'apply.

## Notifier (US09)

`notifier.tf` porte le mapping du stream `tickets` vers l'alias `live` de `notifier` : filtre sur les créations de ticket (`INSERT` de l'élément `META`) et sur les changements de statut candidats (`MODIFY` de l'élément `META` dont les deux images ont un `status`), lots de 10, échecs partiels par élément, bissection, 3 tentatives, 24 h maximum. La politique de lecture du stream (`aws_iam_role_policy.notifier_stream`, clé `data` limitée à DynamoDB et à la table `tickets`) est créée avant le mapping (`depends_on`). La destination d'échec est la file SQS morte de la fonction (chiffrée par la clé `data`), déjà autorisée sur le rôle. Le filtre ne peut pas comparer l'ancien et le nouveau statut : le handler ignore les `MODIFY` sans changement de statut (US09-AC4) et signale les éléments en échec (`batchItemFailures`, US09-AC5). Les e-mails sur commentaire admin (US09-AC2) ne sont pas couverts par ce filtre : à préciser avec SE (forme des éléments `EVENT#`).

## Permissions boundary et issue #98

`permissions_boundary_arn` est obligatoire et non nullable : `lambda-service`, `sla-scheduler` et `knowledge-base` refusent une boundary `null` (seul `attachments-bucket` l'accepte, et seulement sans analyse de malware). Tant que le rôle de l'atelier ne peut pas poser de boundary (issue #98), l'apply de cette stack est bloqué ; le plan et la validation restent possibles.

## Choix de composition

- **Pas de cycle de ressources malgré des modules qui se référencent.** L'identité a besoin de l'URL du site (callback), le site de l'origine API, l'API de l'ARN du user pool (authorizer). Dans le module `identity`, seul le client d'application lit les URL de callback, pas le user pool ; la chaîne se résout donc ressource par ressource. Le domaine hébergé Cognito (CSP du site) est construit depuis son préfixe pour la même raison. De même, le topic `admins` dépend des rôles de `tickets` et `escalation`, jamais l'inverse.
Les quatre choix suivants sont justifiés dans [ADR-0015](../../../docs/adr/0015-platform-stack-wiring.md).

- **`tickets` : la politique d'accès est construite dans la stack** (`data.aws_iam_policy_document.tickets_function`, `iam.tf`), à partir des documents des modules producteurs (table, pièces jointes) et d'instructions qu'aucun module ne publie (clé `data` limitée à S3 et SNS, publication SNS). Un document par fonction : aucune fonction ne dépend des ressources d'une autre.
- **`tickets` : la politique du Scheduler est une `aws_iam_role_policy` en ligne** (`aws_iam_role_policy.tickets_schedules`, `iam.tf`) et non `extra_policy_json`, car `lambda-service` refuse `iam:PassRole` par conception. Le document vient du module `sla-scheduler` : `PassRole` sur le seul rôle d'exécution du Scheduler, vers `scheduler.amazonaws.com`, et `CreateSchedule`/`DeleteSchedule` sur le seul groupe SLA. La boundary de l'environnement doit autoriser ces actions.
- **`kb-sync` lit les identifiants de la Knowledge Base dans SSM à l'exécution** (`KNOWLEDGE_BASE_ID_SSM_PARAMETER`, `DATA_SOURCE_ID_SSM_PARAMETER`). La Knowledge Base dépend de l'alias `kb-sync` (notification S3) : si `kb-sync` dépendait d'elle, l'ordre serait inversé et le premier apply échouerait. Pour la même raison, sa politique d'ingestion est attachée dans la stack (`aws_iam_role_policy.kb_sync_ingestion`).
- **OpenAPI** : `packages/contracts` n'existe pas encore (EN-05). `openapi/openapi.json.tftpl` est un contrat minimal (tickets, kpi, chat) avec l'authorizer Cognito sans scope (jeton d'identité) en attendant EN-32. Le `check "api_routes_match_openapi"` compare ses routes à `local.api_routes`, qui alimentent les permissions d'invocation.
- **Jeton attendu par l'API : le jeton d'identité (ID token) Cognito.** L'authorizer natif n'a pas de scope (voir ci-dessus) : API Gateway valide le jeton d'identité reçu dans l'en-tête `Authorization`, sans préfixe `Bearer`. Un jeton d'accès est refusé tant qu'EN-32 n'a pas défini des scopes. La SPA et les tests Hurl doivent donc envoyer l'ID token.
- **Validation des corps de requête** : les schémas `TicketCreate`, `TicketUpdate` et `ChatMessage` refusent les propriétés inconnues (`additionalProperties: false`).
- **Pas de domaine personnalisé** (ADR-0003) : l'application et l'API sont servies par l'URL `*.cloudfront.net`.

## Variables d'environnement des fonctions (contrat provisoire, à reprendre dans EN-05)

| Fonction | Variables |
| --- | --- |
| `tickets` | `TICKETS_TABLE`, `TICKETS_OWNER_INDEX`, `TICKETS_STATUS_INDEX`, `ATTACHMENTS_BUCKET`, `ATTACHMENTS_PREFIX`, `ATTACHMENTS_MAX_BYTES`, `ATTACHMENTS_CONTENT_TYPES`, `ADMINS_TOPIC_ARN`, `SLA_SCHEDULE_GROUP`, `SLA_SCHEDULER_ROLE_ARN`, `SLA_TARGET_ARN`, `SLA_DLQ_ARN` |
| `chat` | `CHAT_SESSIONS_TABLE`, `CHAT_SESSIONS_OWNER_INDEX`, `CHAT_SESSIONS_TTL_ATTRIBUTE`, `CHAT_RETENTION_DAYS`, `GUARDRAIL_ID`, `GUARDRAIL_VERSION`, et avec la Knowledge Base `KNOWLEDGE_BASE_ID`, `CHAT_MODEL_ID` |
| `escalation` | `TICKETS_TABLE`, `ADMINS_TOPIC_ARN` |
| `kb-sync` | `KNOWLEDGE_BASE_ID_SSM_PARAMETER`, `DATA_SOURCE_ID_SSM_PARAMETER` |
| `kpi`, `kpi-aggregator` | `KPI_TABLE` |
| `notifier`, `pre-token` | aucune pour l'instant |

## Reste à câbler (TODO dans le code)

- **Modules observability, budget, security-baseline** : `ops_publishers` des topics, journaux de CloudFront, alarmes (blocages WAF, profondeur des files d'échec).
- **Tests au niveau composition** : hors périmètre de `task test:unit` (qui ne couvre que les modules). Suivi à créer : tests `tofu test` de la stack avec `mock_provider` (validations de variables, `check`, ordre des ressources).
- **`notifier`** : adresse d'expéditeur (donnée personnelle) à lire dans SSM à l'exécution ; filtre des commentaires admin (US09-AC2) à préciser avec SE.
- **`pre-token`** : la fonction est déployée mais non branchée. Le module `identity` n'a pas d'entrée pour le trigger Lambda, et il n'est pas modifié ici. Tant que le trigger n'est pas câblé (suivi EN-31 / EN-32), **l'obligation de MFA pour le groupe `admin` et le mappage des groupes ne sont pas appliqués** ; le contrôle admin repose sur les groupes Cognito vérifiés dans les handlers.
- **Utilisateurs de test** Cognito et fédération Entra ID (US06).

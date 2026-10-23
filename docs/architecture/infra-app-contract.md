# Contrat infra ↔ app (EN-05)

Interface entre l'infrastructure (OPS, `infra/`) et l'application (SE, `services/`, `frontend/`, `packages/`). L'infra possède la configuration (noms, variables d'environnement, IAM, déclencheurs, runtime, handler), l'app possède le code. Ce document est la source de vérité côté SE ; la source côté infra est `infra/stacks/platform/` (`compute.tf`, `iam.tf`, `ssm.tf`, `locals.tf`).

Aucune valeur d'environnement n'est écrite ici : noms et identifiants se lisent dans les variables d'environnement de la fonction ou dans SSM sous `/smartcampus/<env>/platform/<clé>` (`<env>` = `dev` ou `prod`, préfixe `sc-<env>`). Pas de VPC (ADR-0006) : aucun paramètre réseau.

## 1. Règles communes aux huit fonctions

| Élément | Valeur | Fixé par |
|---|---|---|
| Nom déployé | `sc-<env>-<fonction>` ; lire le nom réel dans `/smartcampus/<env>/platform/lambda/<fonction>/name` | `lambda-service` |
| Architecture | `arm64` uniquement | `lambda-service` |
| Runtime | variable `lambda_runtime`, commune aux huit fonctions ; `python3.13` dans `envs/*/platform.tfvars`, **à confirmer par SE** | SE choisit, OPS applique |
| Handler | variable `lambda_handler`, commune aux huit fonctions, défaut `app.handler` : chaque archive expose `app.py` avec `def handler(event, context)` à sa racine | SE choisit, OPS applique |
| Mémoire / timeout | 256 Mo / 10 s ; `chat` : 512 Mo / 28 s (limite d'intégration API Gateway : 29 s) | `compute.tf` |
| Alias | `live` : seule cible des intégrations (API Gateway, stream, Scheduler, S3) ; jamais `$LATEST` | `lambda-service` |
| Logs | format JSON imposé (`logging_config`), log group `/aws/lambda/sc-<env>-<fonction>` chiffré (clé `logs`), rétention 14 j en dev, 90 j en prod | `lambda-service` |
| Tracing | X-Ray actif | `lambda-service` |
| Variables d'environnement | chiffrées par la clé `data` ; jamais de secret, seulement des noms (suffixe `_SSM_PARAMETER` ou `_SECRET_ARN` pour une valeur lue à l'exécution) | `lambda-service` |
| Rôle | un rôle par fonction, avec la permissions boundary `sc-<env>-workload-boundary` ; droits listés ci-dessous, rien d'autre | `iam.tf` |
| Code initial | archive de remplacement (`placeholder.txt`, sans handler) : toute invocation échoue tant que le pipeline n'a pas déployé le vrai code | `lambda-service` |

Une variable d'environnement ajoutée ou modifiée par OPS crée une nouvelle version, mais `live` ne bouge pas (l'alias appartient au pipeline). Elle n'est visible du code qu'au déploiement applicatif suivant.

## 2. Contrat par fonction

### `tickets` — cycle de vie des tickets (US01, US03, US04, RF01)

- Déclencheur : API REST, intégration `aws_proxy` sur `live` pour `GET /tickets`, `POST /tickets`, `GET /tickets/{ticketId}`, `PATCH /tickets/{ticketId}`.

| Variable | Signification | Source (module) |
|---|---|---|
| `TICKETS_TABLE` | table `tickets` | `tickets-store.table_name` |
| `TICKETS_OWNER_INDEX` | GSI `by-owner` (`ownerSub`, `createdAt`) | `tickets-store.owner_index_name` |
| `TICKETS_STATUS_INDEX` | GSI `by-status` (`status`, `createdAt`) | `tickets-store.status_index_name` |
| `ATTACHMENTS_BUCKET` | bucket des pièces jointes | `attachments-bucket.bucket_name` |
| `ATTACHMENTS_PREFIX` | préfixe des clés (`attachments/`) | `attachments-bucket.attachments_prefix` |
| `ATTACHMENTS_MAX_BYTES` | borne haute de `content-length-range` (10485760) | `attachments-bucket.max_upload_bytes` |
| `ATTACHMENTS_CONTENT_TYPES` | types autorisés, séparés par des virgules (`image/jpeg,image/png`) | `attachments-bucket.allowed_content_types` |
| `ADMINS_TOPIC_ARN` | topic SNS des alertes admins (tickets de sécurité) | `notifications.admins_topic_arn` |
| `SLA_SCHEDULE_GROUP` | groupe de planifications `sc-<env>-sla` | `sla-scheduler.schedule_group_name` |
| `SLA_SCHEDULER_ROLE_ARN` | rôle passé au Scheduler (`RoleArn` de la cible) | `sla-scheduler.scheduler_role_arn` |
| `SLA_TARGET_ARN` | alias `live` de `escalation` (`Arn` de la cible) | `lambda-service` (`escalation.alias_arn`) |
| `SLA_DLQ_ARN` | DLQ de la cible (`DeadLetterConfig.Arn`) | `sla-scheduler.dlq_arn` |

- IAM : `GetItem`, `PutItem`, `UpdateItem` sur la table, `Query` sur la table et ses deux index (pas de `Scan`) ; `s3:GetObject`/`PutObject` sur `<bucket>/attachments/*` ; `sns:Publish` sur le topic admins ; clé `data` via S3 et SNS seulement ; `scheduler:CreateSchedule`/`DeleteSchedule` sur le groupe SLA et `iam:PassRole` du seul rôle Scheduler vers `scheduler.amazonaws.com`.
- Attendu du code :
  - planification SLA à la création (ADR-0008) : `CreateSchedule` dans `SLA_SCHEDULE_GROUP`, `at(<création + 24 h>)` en UTC, `ActionAfterCompletion=DELETE`, `FlexibleTimeWindow=OFF`, nom dérivé de l'identifiant du ticket (idempotent), `Input` limité à l'identifiant du ticket (pas de PII) ;
  - POST pré-signé : une policy signée par type de contenu, conditions du [README attachments-bucket](../../infra/modules/attachments-bucket/README.md#contrat-du-post-pré-signé-en-43-ac2) (`content-length-range`, `Content-Type` en égalité stricte, clé `attachments/<sub>/…` construite côté serveur, sans champ `tagging`) ; pas de `PUT` pré-signé ;
  - catégorie sécurité : priorité `critique` et publication immédiate sur `ADMINS_TOPIC_ARN`.

### `kpi` — tableau de bord (US05, admins)

- Déclencheur : API REST, `GET /kpi`.
- Variable : `KPI_TABLE` (table `kpi`, `kpi.table_name`).
- IAM : `GetItem`, `BatchGetItem`, `Query` sur la table `kpi`, lecture seule ; `kms:Decrypt` via DynamoDB pour cette table seulement.
- Attendu : lecture de O(jours) agrégats, jamais de la table `tickets` ; contrôle du groupe `admin` dans le handler.

### `chat` — assistant RAG (US02, US08, US10, RF03)

- Déclencheur : API REST, `POST /chat`.

| Variable | Signification | Source (module) |
|---|---|---|
| `CHAT_SESSIONS_TABLE` | table `chat-sessions` | `chat-sessions.table_name` |
| `CHAT_SESSIONS_OWNER_INDEX` | GSI `by-owner` (`sub`, `createdAt`) | `chat-sessions.owner_index_name` |
| `CHAT_SESSIONS_TTL_ATTRIBUTE` | attribut TTL (`expiresAt`, epoch en secondes) | `chat-sessions.ttl_attribute_name` |
| `CHAT_RETENTION_DAYS` | rétention RGPD (30 j en dev, à valider PO/BA) | `chat-sessions.retention_days` |
| `GUARDRAIL_ID`, `GUARDRAIL_VERSION` | guardrail Bedrock | `bedrock-guardrail` |
| `KNOWLEDGE_BASE_ID` | Knowledge Base ; **absente si `enable_knowledge_base = false`** (cas du dev aujourd'hui) | `knowledge-base.knowledge_base_id` |
| `CHAT_MODEL_ID` | profil d'inférence (`us.*` en atelier, ADR-0013) ; absente sans Knowledge Base | variable `chat_inference_profile_id` |

- IAM : `GetItem`, `BatchGetItem`, `PutItem`, `UpdateItem`, `DeleteItem`, `Query` sur la table et ses index (pas de `Scan`) ; `bedrock:ApplyGuardrail` sur le guardrail ; avec la Knowledge Base, `bedrock:Retrieve` sur elle et `bedrock:InvokeModel` sur le profil et ses modèles.
- Attendu : écrire `expiresAt = dernière activité + CHAT_RETENTION_DAYS` à chaque écriture et ignorer à la lecture les items expirés ; sans `KNOWLEDGE_BASE_ID`, répondre en mode dégradé (« je ne sais pas » + proposition de ticket) au lieu d'échouer ; sous le seuil de grounding, même réponse (RF03).

### `escalation` — escalade SLA (RF01)

- Déclencheur : EventBridge Scheduler, invocation asynchrone de `live` par la planification créée par `tickets`. Échecs : DLQ SQS de la fonction, plus `SLA_DLQ_ARN` côté Scheduler.
- Variables : `TICKETS_TABLE`, `ADMINS_TOPIC_ARN`.
- IAM : mêmes droits sur la table que `tickets` ; `sns:Publish` sur le topic admins ; clé `data` via SNS.
- Attendu : idempotente, sans effet si le ticket n'est plus `Ouvert`.

### `notifier` — e-mails aux étudiants

- Déclencheur : **aucun pour l'instant** (mapping du stream `tickets` à câbler, TODO de `compute.tf`) ; DLQ SQS prévue.
- Variables : aucune. L'adresse d'expéditeur (PII) sera lue dans SSM à l'exécution (ADR-0015) ; le nom du paramètre arrivera en variable `*_SSM_PARAMETER`.
- IAM : `ses:SendEmail` limité à l'identité SES et à `ses:FromAddress`.
- Bloquant pour SE : le filtre d'événements dépend du contrat de notification à définir par SE (quels changements notifient). Ouvrir une issue `area/infra` avec ce contrat.

### `kb-sync` — ingestion de la Knowledge Base (US07)

- Déclencheur : notification S3 du bucket des documents sources (créations et suppressions), asynchrone ; DLQ SQS. Inexistant tant que `enable_knowledge_base = false`.
- Variables : `KNOWLEDGE_BASE_ID_SSM_PARAMETER`, `DATA_SOURCE_ID_SSM_PARAMETER` (noms de paramètres `String`, lus à l'exécution, ADR-0015).
- IAM : `ssm:GetParameter` sur ces deux paramètres ; avec la Knowledge Base, `StartIngestionJob` et `GetIngestionJob`.
- Attendu : journaliser le statut de l'ingestion.

### `kpi-aggregator` — agrégats journaliers (US05)

- Déclencheur : stream `tickets` (`NEW_AND_OLD_IMAGES`) sur `live`, filtré sur les `INSERT` et les `MODIFY` des items `META` ; échecs partiels par élément, bissection, destination d'échec SQS.
- Variable : `KPI_TABLE`.
- IAM : politique gérée du module `kpi` (lecture du stream, écriture de la table `kpi`, file d'échec, clé `data`).
- Attendu : [contrat du handler du README kpi](../../infra/modules/kpi/README.md#contrat-du-handler-kpi-aggregator-se) (ignorer les `MODIFY` sans changement de statut, idempotence, `UpdateItem` atomique, `batchItemFailures`).

### `pre-token` — déclencheur Cognito (US06)

- Déclencheur : **pas encore câblé** au user pool (TODO US06 de `compute.tf`).
- Variables : aucune ; les domaines e-mail approuvés viendront en variable.
- IAM : aucun droit en plus des logs.
- Attendu : refuser un domaine e-mail non approuvé, mapper les groupes `student` / `admin`.

## 3. Ressources partagées

### Tables DynamoDB (on-demand, PITR, clé `data`)

| Table | Clés | Index | Autres attributs du contrat |
|---|---|---|---|
| `sc-<env>-tickets` | `pk` = `TICKET#<id>`, `sk` = `META` ou `EVENT#<ts>` | `by-owner` : `ownerSub` + `createdAt` ; `by-status` : `status` + `createdAt` | `createdAt` en ISO 8601 ; stream `NEW_AND_OLD_IMAGES` |
| `sc-<env>-chat-sessions` | `sessionId`, `ts` (ISO 8601) | `by-owner` : `sub` + `createdAt` | TTL `expiresAt` (epoch s) ; pas de stream |
| `sc-<env>-kpi` | `pk` (jour), `sk` (dimension : statut, catégorie) | aucun | — |

Les noms d'attributs ci-dessus sont figés par les modules : les changer est une PR infra. Jamais de `Scan`. L'identité d'un étudiant vient toujours du `sub` du JWT, jamais de la requête (OWASP API1).

### Buckets, topics, files

| Ressource | Accès app | Remarque |
|---|---|---|
| Bucket des pièces jointes | `tickets` (préfixe `attachments/`) | privé, TLS seul, POST pré-signé ≤ 10 Mo ; avec `enable_malware_protection`, seuls les objets `NO_THREATS_FOUND` sont lisibles (désactivé en dev) |
| Bucket de la SPA (`site/bucket_name`) | pipeline uniquement | publication de `frontend/`, puis invalidation de `site/distribution_id` |
| Bucket des sources de la KB (`kb/source_bucket_name`) | rôle de déploiement applicatif uniquement | absent sans Knowledge Base |
| Topic `sc-<env>-admins` | `tickets`, `escalation` (`sns:Publish`) | alertes admins |
| Topic `sc-<env>-ops` | aucun | alarmes et budgets |
| DLQ (`escalation`, `notifier`, `kb-sync`, file d'échec `kpi`, `sc-<env>-sla-dlq`) | aucune lecture par le code | alarmes sur la profondeur |

### Paramètres SSM publiés (`/smartcampus/<env>/platform/`, type `String`, aucun secret)

| Clé | Consommateur |
|---|---|
| `api/invoke_url` | tests (QE) ; la SPA passe par `/api/*` sur le domaine CloudFront |
| `site/url`, `site/bucket_name`, `site/distribution_id` | pipeline, tests |
| `identity/user_pool_id`, `identity/client_id`, `identity/hosted_ui_base_url` | configuration de la SPA au build |
| `lambda/<fonction>/name` | pipeline (huit fonctions) |
| `kb/knowledge_base_id`, `kb/data_source_id`, `kb/source_bucket_name` | `kb-sync`, pipeline ; seulement avec `enable_knowledge_base` |

## 4. Contrat d'API

- Source : `packages/contracts` (OpenAPI 3), propriété de SE, relu par QE et OPS. **Le dossier n'existe pas encore** : la stack utilise un contrat minimal provisoire, [`infra/stacks/platform/openapi/openapi.json.tftpl`](../../infra/stacks/platform/openapi/openapi.json.tftpl). Le créer en partant de ce fichier est la première tâche SE (EN-05 AC4), avec son lint dans `task check`.
- Ce que l'infra injecte dans le document : l'ARN du user pool et les invoke ARN des alias `live` de `tickets`, `kpi`, `chat`. Chaque opération garde une intégration `aws_proxy` et `security: [{ "CognitoAuthorizer": [] }]`. Les routes doivent rester égales à `local.api_routes` (`check "api_routes_match_openapi"`) : une route ajoutée = PR contrat + PR infra.
- Validation API Gateway (EN-33) : corps et paramètres validés par les schémas du document (`components.schemas`) ; une requête invalide reçoit un 400 sans invoquer la fonction. Codes à documenter par opération : 400, 401, 403, 404.
- Authentification (ADR-0005, EN-32) : authorizer Cognito natif ; la SPA envoie le jeton dans `Authorization`. Les claims arrivent dans `event.requestContext.authorizer.claims` (`sub`, `email`, `cognito:groups`). Les méthodes admin (`PATCH /tickets/{ticketId}`, `GET /kpi`) vérifient `admin` dans `cognito:groups` dans le handler (403 sinon).
- Événement et réponse : format proxy REST (payload 1.0) ; la fonction renvoie `{ statusCode, headers, body }` avec `body` en chaîne JSON.
- Limites : throttling par stage et par méthode (`chat/POST`, `tickets/POST` plus strictes), WAF régional par IP et par `Authorization` (429).

Points ouverts (à trancher avant le premier déploiement) :

- **Préfixe `/api`** : CloudFront transmet le chemin complet à l'origine (`/api/tickets` → `/v1/api/tickets`, sans réécriture), alors que le contrat provisoire déclare `/tickets`. Via le domaine CloudFront, les routes ne correspondent donc pas. Il faut soit déclarer les chemins sous `/api/…` dans `packages/contracts` (et `local.api_routes`), soit ajouter une réécriture côté edge. Décision OPS + SE, à consigner.
- **Type de jeton** : l'authorizer est déclaré sans scope, ce qui accepte le jeton d'identité ; le module `static-site` documente le jeton d'accès. Le choix (jeton d'identité, ou jeton d'accès avec scopes) revient à EN-32 ; d'ici là, la SPA envoie le jeton d'identité.

## 5. Construire et empaqueter

- Une archive zip par fonction, construite depuis `services/<fonction>/`, pour **Linux arm64** (aarch64).
- Racine du zip : le module du handler (`app.py` pour `app.handler`) et les dépendances à côté, pas de dossier parent. Le code partagé de `packages/` est copié dans chaque archive au build (pas de layer dans le contrat).
- Dépendances natives : binaires `manylinux` aarch64, par exemple `pip install --platform manylinux2014_aarch64 --only-binary=:all: --target build/<fonction> -r requirements.txt`. Le SDK AWS du runtime peut être utilisé, mais l'épingler dans l'archive évite qu'il change sous le code.
- Limites Lambda : 50 Mo zippé en téléversement direct, 250 Mo décompressé.
- Le build se fait en CI (artefact reproductible, nommé d'après le SHA git) ; le mode de publication (téléversement direct ou bucket d'artefacts) est fixé par EN-74.

## 6. Déploiement

### Cible (EN-74, workflow `app-deploy`)

1. Construction de l'archive arm64 de chaque fonction modifiée.
2. `UpdateFunctionCode` sur `sc-<env>-<fonction>`, puis `PublishVersion` : version immuable.
3. Smoke tests (EN-83) sur la nouvelle version.
4. `UpdateAlias live` vers cette version. Les intégrations pointent toujours sur `live`.
5. Rollback : `live` revient à la version précédente (et la SPA précédente est republiée).
6. SPA : build de `frontend/`, synchronisation vers `site/bucket_name`, invalidation de `site/distribution_id`.

dev se déploie depuis `develop`, prod depuis `main` derrière l'approbation de l'environnement GitHub `prod`. OpenTofu ignore le code et la version de l'alias : un plan après déploiement ne montre aucune différence (EN-74 AC5). Le rôle de déploiement applicatif ne peut que mettre à jour le code, publier des versions, déplacer les alias de `sc-<env>-*`, écrire dans le bucket de la SPA et invalider la distribution (EN-74 AC6).

### Aujourd'hui

- `app-deploy` n'est pas fusionné (branche `ci/50-app-deploy`, EN-74 en attente de décision : rôle de déploiement dans le bootstrap ou la foundation).
- L'apply de la stack `platform` est bloqué par l'issue #98 (le rôle de l'atelier ne peut pas poser de permissions boundary) : **aucune fonction n'existe encore dans le compte**, il n'y a donc rien à déployer, même à la main.

### Ce que SE peut faire en attendant

- Créer `packages/contracts` (OpenAPI à partir du contrat provisoire, schémas, codes d'erreur) et l'ouvrir en PR relue par OPS et QE.
- Écrire le code et les tests unitaires de chaque fonction, nommés d'après les critères (`US04-AC2 …`), avec des événements d'exemple : proxy REST avec `requestContext.authorizer.claims`, batch de stream DynamoDB filtré, invocation Scheduler, notification S3, déclencheur Cognito pre-token.
- Exécuter les handlers en local : appel direct de `handler(event, context)` avec les variables de la section 2 renseignées par des valeurs factices, clients AWS simulés (stubs ou mocks). Ne jamais pointer un test local sur le compte AWS avec des identifiants personnels.
- Construire les zips arm64 localement pour valider la structure et la taille.
- Confirmer le runtime (`python3.13` ou autre) et le handler, et décrire le contrat de notification (`notifier`) dans des issues `area/infra`.

## 7. Interdits

- Aucune modification dans la console AWS ni par CLI avec des droits personnels (code, alias, variables, IAM, tables) : tout passe par une PR et la CI (ADR-0009).
- Aucun secret ni PII dans le code, les tests, les variables d'environnement, les logs ou les workflows ; ne jamais lire ni copier `.env`, `~/.aws/*` ou un state.
- Aucun nom de ressource, ARN, compte ou région codé en dur : variables d'environnement et SSM uniquement.
- Pas de `Scan`, pas d'identité prise dans la requête, pas de `PUT` pré-signé ni de champ `tagging` dans le POST.
- Pas de contenu de ticket, de transcription ni d'adresse e-mail en clair dans les logs.
- Pas de nouvel accès AWS dans le code sans issue `area/infra` préalable : le rôle de la fonction refusera l'appel.

## 8. Évolution du contrat

Toute modification (variable, droit, route, attribut, format d'artefact) passe par une PR qui modifie ce document, relue par OPS et SE (CODEOWNERS), et qui référence les issues impactées. Une rupture est marquée `!` dans le titre de PR (Conventional Commits) avec un pied `BREAKING CHANGE:`. Côté infra, la variable ou le droit est ajouté avant que le code ne l'utilise.

## Liens

- ADR [0005](../adr/0005-native-cognito-authorizer.md), [0006](../adr/0006-no-vpc.md), [0008](../adr/0008-per-ticket-sla-scheduler.md), [0009](../adr/0009-gitops-no-local-apply.md), [0013](../adr/0013-workshop-region-us-east-1.md), [0015](../adr/0015-platform-stack-wiring.md)
- README des modules : [`lambda-service`](../../infra/modules/lambda-service/README.md), [`attachments-bucket`](../../infra/modules/attachments-bucket/README.md), [`rest-api`](../../infra/modules/rest-api/README.md), [`kpi`](../../infra/modules/kpi/README.md), [`chat-sessions`](../../infra/modules/chat-sessions/README.md), [`tickets-store`](../../infra/modules/tickets-store/README.md)
- Stack : [`infra/stacks/platform/README.md`](../../infra/stacks/platform/README.md)
- Issues : EN-05, EN-32, EN-33, EN-41, EN-74, EN-83, #98

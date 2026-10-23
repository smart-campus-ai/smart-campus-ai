# 0015 — Câblage de la stack platform : politiques IAM, identifiants de la Knowledge Base et expéditeur SES

- Statut : Proposé
- Date : 2026-10-23
- Décideurs : OPS, AS

## Contexte

La stack `platform` compose les modules de la plateforme (identité, edge, API, données, calcul, IA, notifications). Quatre choix de câblage s'écartent du schéma « un module produit, un module consomme » et conditionnent la sécurité ou le déroulement du déploiement :

- `lambda-service` refuse `iam:PassRole` dans `extra_policy_json` (garde-fou de moindre privilège), alors que `tickets` doit passer le rôle d'exécution du Scheduler à `scheduler.amazonaws.com` pour créer les planifications SLA (RF01, ADR-0008).
- La Knowledge Base a besoin de l'alias `kb-sync` (notification S3), donc `kb-sync` ne peut pas dépendre d'elle sans cycle, alors qu'il doit connaître ses identifiants pour lancer l'ingestion (US07).
- Les politiques d'accès aux données des fonctions viennent de plusieurs modules producteurs, plus des instructions qu'aucun module ne publie.
- L'adresse d'expéditeur SES est une donnée personnelle (règle de sécurité : pas de PII dans le code, les `tfvars` ni les sorties), mais le module `notifications` exige au moins une identité d'expéditeur.

Exigences concernées : RF01, RF04, US07, US09, EN-41, EN-13. Règles : AGENTS.md (briques indépendantes, pas de secret ni de PII dans le dépôt), steering sécurité (moindre privilège, rôles avec permissions boundary).

## Facteurs de décision

- Sécurité : moindre privilège, pas d'assouplissement du garde-fou de `lambda-service`, pas de PII dans le dépôt.
- Fiabilité : premier apply sans cycle de dépendances.
- Indépendance des briques : un module ne découvre pas les ressources d'un autre ; la stack porte la composition.
- Lisibilité de la revue : une politique par fonction, lisible dans un seul fichier.

## Options considérées

1. Politique du Scheduler : (a) `aws_iam_role_policy` en ligne dans la stack, avec le document du module `sla-scheduler` ; (b) autoriser `iam:PassRole` dans `extra_policy_json` de `lambda-service` ; (c) créer la planification côté infrastructure.
2. Identifiants de la Knowledge Base pour `kb-sync` : (a) lecture dans SSM à l'exécution, paramètres publiés par la stack ; (b) variables d'environnement, avec une dépendance de `kb-sync` envers la Knowledge Base ; (c) deuxième apply dédié.
3. Politiques des fonctions : (a) construites dans la stack, un `aws_iam_policy_document` par fonction, fusionnant les documents des modules ; (b) un document partagé par toutes les fonctions ; (c) politiques portées par chaque module producteur.
4. Expéditeur SES : (a) `TF_VAR_sender_email_address` exigée de la CI, jamais dans un `tfvars` ; (b) adresse en clair dans `platform.tfvars` ; (c) domaine d'expéditeur seul (`sender_domain`).

## Décision

1. **Option 1a.** `aws_iam_role_policy.tickets_schedules` (`iam.tf`) attache le document de `sla-scheduler` au rôle de `tickets` : `PassRole` sur le seul rôle d'exécution du Scheduler, vers `scheduler.amazonaws.com`, et `CreateSchedule`/`DeleteSchedule` sur le seul groupe SLA. Le garde-fou de `lambda-service` reste intact (1b l'affaiblirait pour toutes les fonctions) et la planification doit rester par ticket, au runtime (1c contredit ADR-0008).
2. **Option 2a.** `kb-sync` reçoit les noms des paramètres `/smartcampus/<env>/platform/kb/knowledge_base_id` et `.../data_source_id` (variables `*_SSM_PARAMETER`) et les lit à l'exécution, avec `ssm:GetParameter` limité à ces deux ARN. Sa politique d'ingestion, qui dépend de la Knowledge Base, est une `aws_iam_role_policy` en ligne (`kb_sync_ingestion`) pour la même raison. Le coût est un appel SSM par invocation (2b crée un cycle ; 2c rompt le GitOps en un seul apply).
3. **Option 3a.** Les documents sont construits dans `iam.tf` à partir des sorties des modules producteurs (table `tickets`, pièces jointes, sessions de chat, Knowledge Base, notifications) et d'instructions propres à la stack : clé `data` limitée par `kms:ViaService` aux services utilisés, publication SNS. Un document par fonction, pour qu'aucune fonction ne dépende des ressources d'une autre. La table `kpi` suit la même règle : lecture seule pour `kpi`, politique gérée du module `kpi` attachée au rôle de `kpi-aggregator`.
4. **Option 4a.** `sender_email_address` est `sensitive`, sans valeur par défaut ; la CI la fournit par `TF_VAR_sender_email_address` (variable ou secret de l'environnement GitHub). Ni `platform.tfvars`, ni sortie, ni journal ne la contiennent. Le `notifier` la lira dans SSM à l'exécution. Le domaine d'expéditeur (4c) reste possible via `sender_domain` et `sender_local_parts` quand un domaine de messagerie sera disponible.

## Conséquences

- Positives : aucun assouplissement des garde-fous de `lambda-service` ; premier apply sans cycle ; les droits de chaque fonction se relisent dans un seul fichier ; aucune PII dans le dépôt.
- Négatives / dette :
  - la stack contient de la logique IAM (documents et deux politiques en ligne) au lieu de la déléguer entièrement aux modules ; elle doit suivre les évolutions de leurs sorties ;
  - un plan ou un apply sans `TF_VAR_sender_email_address` (ou `sender_domain`) échoue ; la CI et le runbook de déploiement (EN-94) doivent la fournir ;
  - `kb-sync` dépend d'un paramètre SSM publié par la même stack : en cas de lecture avant le premier apply complet, l'ingestion échoue et part en DLQ ;
  - la politique du module `kpi` est attachée en dehors du module et un `depends_on` sur le module serait un cycle : le mapping stream est ordonné après l'attachement par `terraform_data.kpi_aggregator_iam_ready`, qui porte `function_name` (un seul apply ; seule la propagation IAM, éventuellement cohérente, peut encore justifier une relance) ;
  - le mapping du stream `tickets` vers `notifier` est porté par la stack (`notifier.tf`) : filtre sur les créations et les changements de statut candidats, politique de lecture du stream propre au rôle, destination d'échec = file SQS morte chiffrée de la fonction. La comparaison des statuts et l'e-mail sur commentaire admin restent à la charge du handler et de SE ;
  - la fonction `pre-token` est déployée mais non branchée : le module `identity` n'a pas d'entrée pour le trigger Lambda et n'est pas modifié ici. **Tant que le trigger n'est pas câblé (suivi EN-31 / EN-32), l'obligation de MFA pour le groupe `admin` et le mappage des groupes ne sont pas appliqués** ; les handlers contrôlent les groupes `cognito:groups`. Le domaine d'e-mail approuvé (US06) n'est pas non plus imposé ;
  - les politiques en ligne sortent du périmètre des politiques gérées : la permissions boundary de l'environnement (EN-13) doit autoriser `iam:PassRole` vers le Scheduler et `scheduler:CreateSchedule`/`DeleteSchedule`.

## Impact sécurité

Surface d'attaque inchangée. `iam:PassRole` est limité à un rôle, à un service et à un groupe de planifications, et reste interdit à toute autre fonction. Chaque rôle garde la permissions boundary de l'environnement. L'écart de sécurité connu est l'absence du trigger `pre-token` (MFA admin, mappage des groupes), à résoudre avant toute donnée réelle. La protection contre les logiciels malveillants (`enable_malware_protection`) est imposée en prod par une validation de variable, et les ARN de clés KMS lus dans SSM sont contrôlés (compte, région, partition) par un `check`. La clé `data` n'est utilisable que via les services nécessaires, avec contexte de chiffrement pour la table `kpi`. L'adresse d'expéditeur n'est stockée que dans l'environnement de la CI et dans SSM, jamais dans le dépôt ni dans le state en clair (état chiffré, ADR-0011). Les paramètres SSM des identifiants de la Knowledge Base ne sont pas des secrets (identifiants).

## Impact coût

Nul pour les trois premiers choix, hormis un appel SSM par invocation de `kb-sync` (négligeable à l'échelle d'un campus). Pas de coût fixe supplémentaire.

## Liens

- `infra/stacks/platform/README.md`, `infra/stacks/platform/iam.tf`, `infra/stacks/platform/ssm.tf`
- ADR [0008](0008-per-ticket-sla-scheduler.md) : planification unique par ticket
- ADR [0009](0009-gitops-no-local-apply.md) : tous les apply passent par la CI
- ADR [0011](0011-state-backend-bootstrap.md) : chiffrement du state
- ADR [0012](0012-github-oidc-ci-identity.md) : identité CI et permissions boundaries
- RF01, RF04, US07, US09, EN-13, EN-41, EN-94

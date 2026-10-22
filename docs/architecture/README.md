# Architecture v3 — diagrammes

Diagrammes de l'architecture v3 de SmartCampus AI (EN-92), écrits en Mermaid : GitHub les rend nativement et la source versionnée est le rendu (rendu reproductible, aucun export à maintenir). Chaque fichier contient le diagramme, une légende, une description textuelle (accessibilité, EN-92 AC4) et les ADR liés.

| N° | Diagramme | Contenu |
|---|---|---|
| 1 | [Contexte système (C4 niveau 1)](01-contexte-c4.md) | Acteurs, SmartCampus AI, systèmes externes (Entra ID, Bedrock, messageries, GitHub) |
| 2 | [Conteneurs et services AWS](02-conteneurs-aws.md) | CloudFront et ses deux comportements, deux web ACL, Cognito, API REST, Lambdas, DynamoDB, S3 et GuardDuty, Scheduler SLA, SNS/SES, Bedrock KB + S3 Vectors + Guardrail, observabilité |
| 3 | [Flux de déploiement GitOps](03-deploiement-gitops.md) | Bootstrap local, PR et plan, apply dev, release et apply prod, app-deploy |
| 4 | [Frontières de sécurité et identités](04-securite-identites.md) | OIDC et rôles CI, permissions boundaries, zones de confiance, identité utilisateur, CMK par domaine |

## Couverture d'EN-92

| Critère | Où |
|---|---|
| AC1 — Contenu | Diagramme 2 |
| AC2 — Deux formats | Source diagram-as-code et rendu : ces fichiers Mermaid. Fichier drawio : hors de cette tranche, à livrer séparément |
| AC3 — Flux de sécurité | Diagramme 4 (frontières, KMS par domaine, flux d'identité), complété par le diagramme 3 |
| AC4 — Accessibilité | Section « Description textuelle » de chaque fichier, plus `accTitle` / `accDescr` dans les diagrammes flowchart |

## Conventions communes

- Langue : français ; noms de ressources, modules et rôles tels qu'ils figurent dans le code (`sc-<env>-*`, `sc-gha-*`).
- Flèche pleine : appel synchrone ou écriture. Flèche pointillée : événement asynchrone, lecture seule ou flux de logs. Bordure pointillée : composant optionnel derrière une bascule `enable_*`.
- Seuls les services décidés par le steering d'architecture et les ADR figurent ; tout ajout passe par un ADR.

## Décisions représentées

| ADR | Diagrammes |
|---|---|
| [0001](../adr/0001-opentofu.md) OpenTofu | 3 |
| [0002](../adr/0002-single-account-dev-prod.md) Compte unique dev / prod | 3, 4 |
| [0003](../adr/0003-no-custom-domain.md) Pas de domaine personnalisé | 1, 2, 4 |
| [0004](../adr/0004-rest-api-regional-waf.md) API REST et WAF régional | 2, 4 |
| [0005](../adr/0005-native-cognito-authorizer.md) Authorizer Cognito natif | 1, 2, 4 |
| [0006](../adr/0006-no-vpc.md) Pas de VPC | 2, 4 |
| [0007](../adr/0007-s3-vectors.md) S3 Vectors | 1, 2, 4 |
| [0008](../adr/0008-per-ticket-sla-scheduler.md) Scheduler SLA par ticket | 2 |
| [0009](../adr/0009-gitops-no-local-apply.md) GitOps | 1, 3 |
| [0010](../adr/0010-base-pinned-gate-files.md) Fichiers de contrôle épinglés | 3 |
| [0011](../adr/0011-state-backend-bootstrap.md) Backend de state et bootstrap | 3, 4 |
| [0012](../adr/0012-github-oidc-ci-identity.md) Identité CI OIDC et boundaries | 1, 3, 4 |

## Maintenance

- Tout ADR qui modifie l'architecture met à jour le ou les diagrammes concernés dans la même PR et ajoute sa ligne au tableau ci-dessus.
- Vérifier le rendu dans l'aperçu de la PR GitHub avant fusion ; GitHub affiche une erreur à la place d'un diagramme invalide.

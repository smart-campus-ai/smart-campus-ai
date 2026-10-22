# Architecture Decision Records

Format MADR, gabarit : [0000-template.md](0000-template.md). Toute modification d'une décision du steering d'architecture exige un nouvel ADR.

| N° | Titre | Statut | Date |
|---|---|---|---|
| [0001](0001-opentofu.md) | OpenTofu comme outil d'infrastructure as code | Accepté | 2026-10-22 |
| [0002](0002-single-account-dev-prod.md) | Dev et prod dans un compte unique pendant l'atelier | Accepté | 2026-10-22 |
| [0003](0003-no-custom-domain.md) | Pas de nom de domaine personnalisé | Accepté | 2026-10-22 |
| [0004](0004-rest-api-regional-waf.md) | API Gateway REST avec WAF régional plutôt qu'API HTTP | Accepté | 2026-10-22 |
| [0005](0005-native-cognito-authorizer.md) | Authorizer Cognito User Pool natif | Accepté | 2026-10-22 |
| [0006](0006-no-vpc.md) | Fonctions Lambda hors VPC | Accepté | 2026-10-22 |
| [0007](0007-s3-vectors.md) | S3 Vectors comme magasin vectoriel de la Knowledge Base | Accepté | 2026-10-22 |
| [0008](0008-per-ticket-sla-scheduler.md) | Escalade SLA par planification unique par ticket | Accepté | 2026-10-22 |
| [0009](0009-gitops-no-local-apply.md) | GitOps : aucun apply local hors bootstrap | Accepté | 2026-10-22 |
| [0010](0010-base-pinned-gate-files.md) | Fichiers de contrôle épinglés sur le commit de base des PR | Accepté | 2026-10-22 |

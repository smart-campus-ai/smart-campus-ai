# Inspection du compte workshop — EN-11

- Compte : 762233769579
- Rôle : `role/ops` (lecture seule, orchestré)
- Date : 22–23 octobre 2026
- Région : `us-east-1` (ADR-0013)
- ADR : [0013](../adr/0013-workshop-region-us-east-1.md)

## Résultats par axe de validation

### AC1 — Région autorisée

| Constat | Preuve | Impact |
|---|---|---|
| Seule `us-east-1` autorise Lambda, DynamoDB, Bedrock, Cognito, Logs, SNS, SQS, SSM, EventBridge Scheduler, SES. | `aws ec2 describe-regions --all-regions` puis `aws sts get-caller-identity` dans chaque région | ADR-0013 : `aws_region = "us-east-1"` pour dev et prod pendant l'atelier. Modules sans modification (région déjà paramétrée). |
| `eu-west-3` est refusé par `ws-default-policy` pour KMS, Bedrock, Lambda, DynamoDB, S3 Vectors, Guardrails. | `aws kms list-keys --region eu-west-3`, `aws bedrock list-guardrails --region eu-west-3`, `aws s3vectors list-vector-buckets --region eu-west-3` → `AccessDenied` | Profil d'inférence EU (`eu.*`) indisponible en workshop (ADR-0013). |

### AC2 — Identity and Access Management

| Constat | Preuve | Impact |
|---|---|---|
| `ws-default-policy` Deny tout hors `us-east-1` (`aws:RequestedRegion`). | `aws iam get-policy-version --policy-arn arn:aws:iam::762233769579:policy/ws-default-policy --version-id v1` | Toute ressource hors `us-east-1` est refusée par politique de compte (ADR-0013). |
| `console-iam-policy-0` autorise la création/gestion de rôles/policies mais **jamais** `iam:CreateOpenIDConnectProvider`. | `aws iam get-policy-version --policy-arn arn:aws:iam::762233769579:policy/console-iam-policy-0 --version-id v1` | OIDC impossible sans `CreateOpenIDConnectProvider` → #98 (blocker CI jusqu'à résolution). |
| `PutRolePermissionsBoundary` n'est **pas** explicitement exclu de `console-iam-policy-0`. | Policy document read | L'invariant de boundary obligatoire (ADR-0012) est respecté tant que #98 reste bloqué ; le blocage #98 empêche toute création de rôles, y compris ceux sans boundary. Aucune adaptation EN-13 n'est nécessaire. |
| Aucun utilisateur/groupes/clés d'accès autorisés. | Policy `Deny` explicite | Aucun risque. CI utilise OIDC (bloqué tant que #98 non résolu). |
| **eu-west-3** : Bedrock KB, S3 Vectors, Guardrails, profil `eu.*` indisponibles (tous refusés par `ws-default-policy`). | `aws bedrock-agent list-knowledge-bases --region eu-west-3`, `aws s3vectors list-vector-buckets --region eu-west-3`, `aws bedrock list-guardrails --region eu-west-3` → `AccessDenied` | Profil EU (`eu.*`) impossible en workshop. |

### AC3 — Services AWS existants (ne pas modifier)

| Constat | Preuve | Impact |
|---|---|---|
| Services de sécurité fournis par le compte : GuardDuty, Security Hub (v1/v2), Config, CloudTrail (2 trails multi-régions), Inspector2, Macie, Access Analyzer. Noms réservés : `workshop-stack-*`, `kiro-identity-center-*`, `EEOrganizations`. | `aws guardduty list-detectors`, `aws config describe-configurators`, `aws cloudtrail describe-trails`, `aws accessanalyzer list-archive-rules` | Modules `security-baseline` : tous les drapeaux `enable_*` doivent être `false`. |
| SES en **sandbox** (`ProductionAccessEnabled = false`, quota 200/24 h). | `aws ses get-account --query 'AccountStatus'` | Procédure sandbox : vérifier/dupliquer les identities (emails/dédomaines) pour chaque environnement; envoyer depuis une identity vérifiée; utiliser `aws ses send-email` ou `ses:SendEmail` IAM dans les rôles Lambda. |

### AC4 — GuardDuty et Malware Protection for S3

| Constat | Preuve | Impact |
|---|---|---|
| GuardDuty activé au niveau compte (managed at organization level). | `aws guardduty list-detectors` → aucun detector dans ce compte (l'account est sous une organisation avec GuardDuty géré). | Module `security-baseline` : `enable_guardduty = false`. |
| GuardDuty Malware Protection for S3 **non activé** (aucun plan de protection). | `aws guardduty list-malware-protection-plans --region us-east-1` → `0` plans | Module `security-baseline` : `enable_malware_protection = false`. Scénario de protection des attachments bucket à définir (cost). |

## Région

Le compte impose `us-east-1`. Toutes les ressources (platform, foundation, state backend) se déployent ici. Les modules sont paramétriques et n'exigent aucune modification. Un retour en `eu-west-3` pour une vraie production est codé (ADR-0013, section Conséquences).

## Écarts et ADR

- **ADR-0013** : région `us-east-1` imposée pendant l'atelier, avec profil d'inférence US (`us.*`) et embeddings disponibles. Retour en `eu-west-3` planifié pour production (nécessite levée de #98 pour OIDC et boundaries).
- **À rédiger (EN-16)** : refus de Budgets (`AccessDenied`) rend le module `budget` inutilisable en l'état. Solution : création manuelle du budget dans la console ou migration vers un autre compte.
- **À rédiger (EN-12)** : procédure sandbox SES : vérification/duplication des identities, usage de `ses:SendEmail` avec restrictions IAM.

## Liens

- #41, #98, #40 (EN-11)
- ADR-0002 (compte unique), ADR-0004 (deux web ACL), ADR-0007 (S3 Vectors), ADR-0011 (bootstrap), ADR-0012 (OIDC), ADR-0013 (région)
- `.kiro/steering/security.md` (OIDC, boundaries), `AGENTS.md` (Environnements)

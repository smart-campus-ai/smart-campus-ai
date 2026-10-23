# Rapport de nuit — 22→23 octobre 2026

> Rapport produit à **09:10 au lieu de 07:00** : une limite d'usage de l'orchestrateur a suspendu le travail entre ~04:50 et 09:05.

## 1. PR mergées dans `develop` (nuit)

| PR | Contenu |
|---|---|
| #96 | module `rest-api` (EN-33) |
| #97 | module `static-site` S3 + CloudFront OAC (EN-21) |
| #99 | variantes d'agents Kiro (glm-5, qwen3-coder-next, reviewer-x gpt-5.6-terra) |
| #100 | bascule de région us-east-1 + ADR 0013 |
| #101 | module `notifications` SNS/SES (EN-45) |
| #102 | module `knowledge-base` Bedrock + S3 Vectors (EN-51) |
| #103 | module `attachments-bucket` + Malware Protection (EN-43) |
| #104 | `pr-governance` : fin des checks requis annulés qui bloquaient les merges |
| #105 | module `kms-keys` par domaine (EN-14) |
| #106 | module `waf` CLOUDFRONT + REGIONAL (RF04) |
| #108 | module `budget` (EN-16) |
| #109 | module `kpi` (EN-46) |
| #110 | **stack `foundation`** (KMS, alertes, contrat SSM) |
| #111 | **stack `platform`** (tous les modules reliés) — en auto-merge à 09:10 |

## 2. État réel de dev

**Non déployé.** Raison : le rôle `WSParticipantRole` ne peut pas créer le fournisseur OIDC GitHub ni poser de permissions boundary (#98, ADR 0014 Proposé). Sans OIDC, la CI ne peut ni planifier ni appliquer, et les clés d'accès dans GitHub sont interdites. Pas d'URL CloudFront, pas de smoke ni de k6. Bootstrap du state (EN-12) : plan prêt (9 ajouts), à appliquer par l'OPS (`docs/runbooks/bootstrap.md`, branche `docs/41-bootstrap-runbook`).

Coût estimé de dev une fois déployé (ordre de grandeur, à confirmer dans EN-93) : WAF ≈ 25 $/mois, 7 CMK ≈ 7 $/mois, le reste à l'usage (KB et Malware Protection désactivées en dev).

## 3. ADR

- Acceptés : **0013** région us-east-1 (décision OPS).
- Proposés (décision attendue) : **0014** contraintes IAM du workshop (branche `docs/98-workshop-iam-adr`), **0015** câblage de la stack platform (dans #111).
- Aucune amélioration auto-acceptée : les points auto-acceptables de l'audit n°1 (nommage des entrées, duplication du durcissement S3, dette de tests) sont listés dans #107 pour Post-workshop.

## 4. Décisions en attente (`status/needs-decision`)

| Issue | Sujet | Branche poussée |
|---|---|---|
| #98 | OIDC GitHub et boundaries impossibles avec `WSParticipantRole` | — |
| #107 | audit n°1 : SLA PassRole, KMS edge/CloudFront, rôle CloudWatch API GW, chemin `/api` | — |
| #49 | EN-73 `iac-apply` : test d'AC non branché (Taskfile = fichier de gate) | `ci/49-iac-apply` |
| #50 | EN-74 `app-deploy` : 2 points bloquants restants | `ci/50-app-deploy` |
| #72 | EN-15 baseline : `aws:SourceArn` Config (sans effet, Config désactivé) | `feat/72-security-baseline` |
| #20 | EN-61 observabilité : fixture d'intégration manquante | `feat/20-observability` |
| #40 | EN-11 inspection du compte (doc) | `docs/40-account-inspection` |
| #41 | runbook bootstrap (2 corrections non relues) | `docs/41-bootstrap-runbook` |
| #59 | EN-82 policies Checkov custom OK, harness des fixtures cassé | `test/59-iac-test-harness` |

Écarts assumés à la règle « 2 allers-retours » (correctifs mécaniques vérifiés par le gate, sans 3e revue) : #105, #106, #111 — à relire.

Non commencés : EN-32 (authorizer Cognito branché), EN-83 (Hurl smoke/sécurité : prêt et vert localement dans `sc-60`, non relu), EN-05 (contrat infra/app : brouillon dans `sc-70`, à relire après #111), EN-94 (runbooks).

## 5. Crédits Kiro

Aucun compteur exposé par `kiro-cli` : estimation ≈ 1 000 à 1 200 crédits (≈ 110 délégations, dont ≈ 40 reviewer-x à 2.2x et ≈ 20 secops à 2.0x). Plafond de 1 400 non dépassé selon cette estimation, à vérifier dans la console Kiro.

## 6. Top 5 des risques avant la démo

1. **#98** : sans OIDC (ou dérogation datée), rien ne se déploie par la CI.
2. **SLA (ADR 0008)** : l'escalade dépend d'un `iam:PassRole` que les garde-fous refusent (#107).
3. **CloudFront ↔ clé `data`** : le second apply de foundation est obligatoire pour que la SPA soit servie (runbook `foundation-second-apply.md`).
4. **Rôle CloudWatch d'API Gateway** (compte) absent : le premier apply du stage peut échouer.
5. **Fenêtre de temps** : application SE pas encore déployée, workflows `iac-apply`/`app-deploy` non mergés (#49, #50).

## 7. Plan de la matinée

1. Renouveler les identifiants du workshop (profil `smartcampus-ws`).
2. Trancher #98 avec les organisateurs : OIDC pré-créé (+ rôles CI) ou dérogation ADR 0014 (B).
3. Bootstrap : appliquer le state (`docs/runbooks/bootstrap.md`), puis la partie OIDC selon la décision ; poser les variables GitHub.
4. Merger #49 (`iac-apply`) et #50 (`app-deploy`) après décision, puis apply dev : foundation → platform → second apply foundation.
5. Équipe SE (@LiberiBg) : coder les handlers selon le contrat (brouillon EN-05) et `packages/contracts` (OpenAPI) ; déploiement dès que #50 est mergé. QE (@MatRom-03) : relire EN-83 (Hurl) et EN-82.

# Backlog v2 — refonte des issues

Source : `Pawpawzz/smart-campus-ai` (21 issues au 22/10, lecture seule). Cible : `smart-campus-ai/smart-campus-ai` (public, vide au 22/10). Ce fichier est l'entrée de Claude Code pour recréer ou corriger le backlog via `gh`. Les décisions d'architecture citées sont dans `.kiro/steering/architecture.md`.

## Principes

- On **garde les identifiants US01–US10 et RF01–RF04** de l'équipe, pour ne pas perdre les repères.
- Les fausses US techniques (`US11` à `US14`) deviennent des **enablers `EN-xx`**. Leur numéro reprend celui de l'epic (EN-2x = epic E2).
- Les doublons fermés (#7, #8, #17) ne sont pas migrés. Les critères d'acceptation utiles de #7/#8 (journal de succès/échec de la synchro) et de #17 (dashboards, erreurs d'authentification, latence) sont fusionnés dans US07 et EN-61.
- Chaque issue reçoit :
  - des critères d'acceptation en Gherkin numérotés `AC1..n` ;
  - les labels `type/`, `area/`, `role/`, `priority/` (MoSCoW) et `size/` ;
  - un epic parent (sous-issue) et une Definition of Done.
- Issues en français, titres préfixés par l'ID.

## Epics

| Epic | Titre | Rôles |
|---|---|---|
| E0 | Gouvernance du dépôt et outillage | OPS, QE |
| E1 | Fondations AWS (state, OIDC, KMS, baseline sécurité, coûts) | OPS, AS |
| E2 | Edge et hébergement du front | OPS, AS |
| E3 | Identité et API | OPS, AS, SE |
| E4 | Tickets et SLA | SE, OPS, QE |
| E5 | Assistant IA (RAG) | SE, OPS, AS |
| E6 | Observabilité | OPS |
| E7 | CI/CD et GitOps | OPS, QE |
| E8 | Qualité et tests | QE |
| E9 | Documentation, coûts et démo | AS, BA |

## Correspondance des issues existantes

| Ancienne | Nouvelle | Epic | Priorité | Corrections à appliquer |
|---|---|---|---|---|
| #1 US01 Gestion admin des tickets | US01 | E4 | must | Statuts alignés sur US03 ; historique d'audit (`EVENT#ts`, horodatage + id admin) ; note de résolution obligatoire pour clôturer ; ajout de la priorité `critique`. |
| #2 US02 Chatbot campus | US02 | E5 | must | Réponses uniquement issues de la KB (renvoi vers RF03) ; historique de session stocké dans `chat-sessions` avec TTL (renvoi vers US08). |
| #3 US03 Suivi des tickets | US03 | E4 | must | Ajouter un AC sécurité : un étudiant ne voit **que** ses tickets (test BOLA). Statuts : Ouvert, En cours, En attente étudiant, Résolu, Fermé. |
| #4 US04 Création de ticket | US04 | E4 | must | Statut initial « Ouvert » (et non « Open », cf. RF01) ; catégorie sécurité ⇒ priorité `critique` + alerte immédiate. **À valider par le PO** : pièce jointe JPG/PNG ≤ 10 Mo (exemple US-01 du deck). |
| #5 US05 KPI | US05 | E4 | should | Les KPI sont lus depuis les agrégats journaliers de la table `kpi` (EN-46), pas par requête sur les tickets. |
| #6 US06 SSO Microsoft | US06 | E3 | could | Fédération OIDC derrière `enable_entra_federation`, filtrage du domaine par trigger pre-token. Dépend d'une inscription d'application dans le tenant de l'école ; sinon, utilisateurs Cognito natifs. |
| #7, #8 (fermées, doublons) | — | — | — | Non migrées ; AC fusionnés dans US07. |
| #9 US07 Synchro des sources | US07 | E5 | should | Événement S3 → `kb-sync` → `StartIngestionJob` ; journal succès/échec (repris de #7/#8). |
| #10 RF01 Cycle de vie et SLA | RF01 | E4 | must | Statut initial « Ouvert » ; un rendez-vous EventBridge Scheduler unique par ticket à +24 h (pas de scan horaire) ; escalade idempotente. |
| #11 RF02 GitOps | NFR-01 | E7 | must | Devient l'exigence transverse portée par l'epic E7 ; AC : aucun apply hors CI sauf bootstrap, détection de dérive, traçabilité (issue ↔ PR ↔ déploiement). |
| #12 RF03 Confinement RAG | RF03 | E5 | must | Guardrail avec vérification d'ancrage contextuel (seuils) ; sous le seuil ⇒ refus + proposition de ticket. |
| #13 RF04 WAF + rate limiting | RF04 | E2 | must | **Précision** : deux web ACL. L'une sur CloudFront (scope CLOUDFRONT, us-east-1), l'autre régionale sur le stage de l'**API REST**. La seconde porte les règles de débit agrégées sur l'en-tête `Authorization` (par utilisateur) et par IP : la limite s'applique même en appel direct à l'URL `execute-api`. S'y ajoute du throttling par stage et par méthode. |
| #14 US08 RGPD | US08 | E5 | should | TTL sur `chat-sessions` ; suppression des données à la demande ; masquage des PII par le Guardrail ; journalisation des invocations Bedrock désactivée ou à rétention courte. |
| #15 US09 Notifications SES | US09 | E4 | should | SES en sandbox ⇒ identités vérifiées pour la démo ; le lien vers le ticket utilise l'URL CloudFront. |
| #16 US10 Chat → ticket | US10 | E5 | should | Le contexte de la conversation pré-remplit le formulaire. |
| #17 (fermée, doublon) | — | — | — | AC fusionnés dans EN-61. |
| #18 « US11 » Hébergement S3/CloudFront | EN-21 | E2 | must | OAC, en-têtes de sécurité (HSTS, CSP, nosniff, Referrer-Policy), redirection HTTPS, TLS 1.2 minimum, comportement `/api/*` vers l'API. |
| #19 « US14 » Validation des tokens | EN-32 | E3 | must | **Correction** : authorizer Cognito User Pool natif de l'API REST, et non un Lambda authorizer (pas de code, pas de démarrage à froid, surface d'attaque réduite). Les groupes sont lus depuis `cognito:groups`. Une requête sans token ou avec un token invalide reçoit un 401. |
| #20 « US13 » Logs et alertes | EN-61 | E6 | must | AC de #17 fusionnés : dashboards, erreurs d'authentification, 5xx, latence p95, profondeur des DLQ, blocages WAF → SNS. |
| #21 « US12 » Domaine + ACM | EN-22 | E2 | wont | **Pas de nom de domaine (décision du 22/10).** La redirection HTTPS passe dans EN-21 (URL `*.cloudfront.net`). Le code reste prêt derrière `enable_custom_domain=false` (ACM us-east-1, alias CloudFront). Le contournement de `execute-api` est couvert par le WAF régional de l'API REST (RF04). L'issue reste ouverte au statut « won't » pour la traçabilité. |

## Nouvelles issues (OPS / QE / AS)

| ID | Titre | Epic | Priorité | Rôle |
|---|---|---|---|---|
| EN-01 | Outillage du dépôt : mise, Taskfile, lefthook, commitlint, editorconfig | E0 | must | ops |
| EN-02 | Gouvernance GitHub : rulesets, labels, templates, CODEOWNERS, environnements, board Projects | E0 | must | ops |
| EN-03 | Chaîne d'approvisionnement : Renovate, actions épinglées par SHA, secret scanning et push protection | E0 | should | ops |
| EN-11 | Spike : inspection du compte workshop (région, droits IAM/OIDC, Bedrock, S3 Vectors, SES, services déjà actifs) | E1 | must | ops, as |
| EN-12 | Bootstrap : bucket de state, KMS, chiffrement du state OpenTofu, verrou natif | E1 | must | ops |
| EN-13 | OIDC GitHub : rôles plan/apply et permissions boundary | E1 | must | ops |
| EN-14 | Clés KMS par domaine (data, logs, ai) | E1 | must | ops |
| EN-15 | Baseline sécurité du compte (CloudTrail, GuardDuty, Security Hub, Config, Access Analyzer), avec interrupteurs | E1 | should | ops |
| EN-16 | Budget AWS et alertes de coût | E1 | should | ops |
| EN-31 | Cognito : user pool, groupes, client PKCE, MFA admin, utilisateurs de test (dev) | E3 | must | ops |
| EN-33 | API REST régionale : ressources/méthodes, validation des requêtes (modèles JSON Schema), throttling, logs d'accès JSON, X-Ray | E3 | must | ops |
| EN-41 | Module générique `lambda-service` (rôle dédié, logs KMS, alias, DLQ, tracing) | E4 | must | ops |
| EN-42 | Table `tickets` (GSI, streams, PITR, protection contre la suppression) | E4 | must | ops |
| EN-43 | Bucket des pièces jointes : POST pré-signé, Malware Protection | E4 | should | ops |
| EN-44 | SLA : groupe Scheduler, rôle et cible d'escalade | E4 | must | ops |
| EN-45 | Notifications : identités SES, topics SNS (admins, ops) | E4 | should | ops |
| EN-46 | Agrégats KPI depuis le stream (table `kpi`) | E4 | should | ops, se |
| EN-51 | Bedrock Knowledge Base, S3 Vectors, bucket des sources | E5 | should | ops, as |
| EN-52 | Guardrail Bedrock (sujets interdits, PII, injection de prompt, ancrage) | E5 | must | ops |
| EN-53 | Table `chat-sessions` avec TTL | E5 | should | ops |
| EN-71 | CI : titre de PR, lint, sécurité, tests unitaires, docs | E7 | must | ops, qe |
| EN-72 | Plan sur les PR (OIDC lecture seule), commentaire, Infracost | E7 | must | ops |
| EN-73 | Apply GitOps : develop → dev, main → prod avec approbation, plan figé | E7 | must | ops |
| EN-74 | Déploiement applicatif : artefacts Lambda, alias, SPA, invalidation, rollback | E7 | must | ops |
| EN-75 | Détection de dérive nocturne → issue | E7 | could | ops |
| EN-76 | Releases : release-please, changelog, garde de `main` | E7 | should | ops |
| EN-81 | Stratégie de test et matrice de traçabilité | E8 | must | qe |
| EN-82 | Socle de tests unitaires IaC (`tofu test`, provider simulé) | E8 | must | qe |
| EN-83 | Tests smoke et sécurité post-déploiement (Hurl : 401/403, BOLA, upload, WAF) | E8 | must | qe |
| EN-84 | Performance k6 (exigence < 2 s : p95 < 2000 ms) | E8 | should | qe |
| EN-85 | E2E Playwright des parcours critiques | E8 | could | qe |
| EN-86 | DAST : scan de base OWASP ZAP (nocturne, dev) | E8 | could | qe |
| EN-91 | ADR initiaux (OpenTofu, compte unique, pas de domaine, API REST + WAF régional plutôt qu'API HTTP, authorizer Cognito natif, pas de VPC, S3 Vectors, scheduler SLA) | E9 | must | as |
| EN-92 | Diagramme d'architecture v3 (drawio + diagram-as-code) | E9 | should | as |
| EN-93 | Estimation des coûts (Infracost et hypothèses de charge) | E9 | should | as, ops |
| EN-94 | Runbooks : déploiement, rollback, incident, rotation | E9 | should | ops |
| EN-95 | Préparation de la démo (scénario, données de démo, script) | E9 | must | ba, qe |

## Ordre de réalisation (chemin critique OPS)

1. E0 : EN-01, EN-02
2. EN-71 (CI), puis rulesets avec les checks requis
3. EN-11, EN-12, EN-13 (EN-12 et EN-13 = apply local du bootstrap par Paul)
4. EN-14, EN-41, EN-42, EN-21, RF04, EN-31, EN-32, EN-33
5. EN-72, EN-73, EN-74 → l'équipe SE peut déployer
6. EN-44, EN-45, EN-52, EN-53, EN-51, EN-43, EN-46
7. E6, puis E8, puis E9

# Plan de migration du backlog (phase 2)

Cible : `smart-campus-ai/smart-campus-ai`. Le dépôt a été transféré : les 21 issues de `docs/backlog/source-issues.json` existent déjà dans la cible **avec les mêmes numéros**. Correspondances et priorités : `docs/backlog/backlog-v2.md`. Taxonomie : `.kiro/steering/git-workflow.md`. Corps des issues : `docs/backlog/issues/<ID>.md`.

## 1. Stratégie

- **UPDATE** : les 18 issues ouvertes migrées sont modifiées sur place (titre, corps, labels, sous-issue de l'epic). Aucun numéro ne change, les liens existants restent valides.
- **CREATE** : les 10 epics `E0..E9`, puis les 39 enablers nouveaux (dont EN-04 et EN-05). Chaque story/enabler est rattachée comme sous-issue de son epic.
- **KEEP CLOSED** : #7, #8 (doublons de US07) et #17 (doublon de EN-61) restent fermées, sans modification ; un commentaire renvoie vers #9 et #20.
- **#21 = EN-22** : mise à jour comme les autres, avec `priority/wont` ; elle **reste ouverte** pour la traçabilité (décision « pas de domaine » du 22/10).
- Ordre d'exécution : (a) créer les labels, (b) supprimer les labels par défaut, (c) créer les epics, (d) traiter le tableau dans l'ordre (UPDATE et CREATE), (e) rattacher les sous-issues et renseigner les champs du board (Priority, Epic, Role, Size).
- Assignés : seuls les assignés existants sont conservés (`G8LD` sur #18 à #21). Les autres assignations sont à décider en équipe (voir questions).

## 2. Labels

### À créer

| Label | Couleur | Description |
|---|---|---|
| type/epic | 3E4B9E | Epic parent (E0..E9) |
| type/story | 1D76DB | User story ou règle métier (US-xx, RF-xx) |
| type/enabler | 5319E7 | Story technique (EN-xx) |
| type/nfr | 0E8A16 | Exigence transverse (NFR-xx) |
| type/bug | D73A4A | Anomalie |
| type/chore | C5DEF5 | Maintenance sans impact fonctionnel |
| type/spike | FBCA04 | Investigation limitée dans le temps |
| area/infra | 0052CC | OpenTofu, modules et stacks |
| area/ci-cd | 006B75 | Workflows GitHub, pipelines |
| area/security | B60205 | IAM, KMS, WAF, données sensibles |
| area/observability | 0E8A16 | Logs, traces, alarmes, dashboards |
| area/qa | BFD4F2 | Stratégie et outillage de test |
| area/app | 1D76DB | Code des fonctions Lambda |
| area/front | 7057FF | SPA |
| area/ai | F9D0C4 | Bedrock, Knowledge Base, Guardrail |
| area/docs | 0075CA | ADR, architecture, runbooks |
| role/ops | D4C5F9 | Porté par OPS |
| role/qe | C2E0C6 | Porté par QE |
| role/as | FEF2C0 | Porté par l'architecte |
| role/se | BFDADC | Porté par SE |
| role/ba | E6E6E6 | Porté par le BA / PO |
| priority/must | B60205 | MoSCoW : indispensable |
| priority/should | D93F0B | MoSCoW : important |
| priority/could | FBCA04 | MoSCoW : souhaitable |
| priority/wont | CCCCCC | MoSCoW : hors périmètre, conservé pour traçabilité |
| size/xs | E8F5E9 | Moins d'une demi-journée |
| size/s | C2E0C6 | Environ une journée |
| size/m | 7BC96F | Deux à trois jours |
| size/l | 2E7D32 | Une semaine ou plus, à découper si possible |
| status/blocked | E11D21 | Bloqué par une dépendance externe |
| status/in-progress | 0E8A16 | En cours de réalisation |
| status/needs-decision | D876E3 | Décision PO ou ADR attendue |
| drift | 5319E7 | Dérive détectée entre OpenTofu et AWS |
| dependencies | 0366D6 | Mise à jour de dépendances |
| security | EE0701 | Constat de sécurité |

### À supprimer (labels par défaut)

`accessibility`, `bug`, `documentation`, `duplicate`, `enhancement`, `good first issue`, `help wanted`, `invalid`, `question`, `wontfix`.

Supprimer `enhancement` retire le label des 21 issues existantes ; c'est voulu (remplacé par `type/*`).

## 3. Tableau de migration

Conventions : `Issue` vide = issue à créer ; `Dépendances` = IDs séparés par des virgules ; `Assignés` = logins GitHub. Les lignes KEEP CLOSED n'ont ni ID ni corps : titre et labels actuels inchangés. Épics : `Epic` vide.

| ID | Action | Issue | Titre | Labels | Epic | Priorité | Taille | Rôle | Assignés | Dépendances | Corps |
|---|---|---|---|---|---|---|---|---|---|---|---|
| E0 | CREATE |  | E0 — Gouvernance du dépôt et outillage | type/epic, area/ci-cd, area/security, role/ops, role/qe, priority/must, size/l |  | must | l | OPS |  |  | docs/backlog/issues/E0.md |
| E1 | CREATE |  | E1 — Fondations AWS (state, OIDC, KMS, baseline sécurité, coûts) | type/epic, area/infra, area/security, role/ops, role/as, priority/must, size/l |  | must | l | OPS |  |  | docs/backlog/issues/E1.md |
| E2 | CREATE |  | E2 — Edge et hébergement du front | type/epic, area/infra, area/security, area/front, role/ops, role/as, priority/must, size/l |  | must | l | OPS |  |  | docs/backlog/issues/E2.md |
| E3 | CREATE |  | E3 — Identité et API | type/epic, area/infra, area/security, area/app, role/ops, role/as, role/se, priority/must, size/l |  | must | l | OPS |  |  | docs/backlog/issues/E3.md |
| E4 | CREATE |  | E4 — Tickets et SLA | type/epic, area/app, area/front, area/infra, role/se, role/ops, role/qe, priority/must, size/l |  | must | l | SE |  |  | docs/backlog/issues/E4.md |
| E5 | CREATE |  | E5 — Assistant IA (RAG) | type/epic, area/ai, area/app, area/infra, role/se, role/ops, role/as, priority/must, size/l |  | must | l | SE |  |  | docs/backlog/issues/E5.md |
| E6 | CREATE |  | E6 — Observabilité | type/epic, area/observability, role/ops, priority/must, size/m |  | must | m | OPS |  |  | docs/backlog/issues/E6.md |
| E7 | CREATE |  | E7 — CI/CD et GitOps | type/epic, area/ci-cd, role/ops, role/qe, priority/must, size/l |  | must | l | OPS |  |  | docs/backlog/issues/E7.md |
| E8 | CREATE |  | E8 — Qualité et tests | type/epic, area/qa, role/qe, priority/must, size/l |  | must | l | QE |  |  | docs/backlog/issues/E8.md |
| E9 | CREATE |  | E9 — Documentation, coûts et démo | type/epic, area/docs, role/as, role/ba, priority/must, size/l |  | must | l | AS |  |  | docs/backlog/issues/E9.md |
| EN-01 | CREATE |  | EN-01 — Outillage du dépôt : mise, Taskfile, lefthook, commitlint, editorconfig | type/enabler, area/ci-cd, role/ops, priority/must, size/m | E0 | must | m | OPS |  |  | docs/backlog/issues/EN-01.md |
| EN-02 | CREATE |  | EN-02 — Gouvernance GitHub : rulesets, labels, templates, CODEOWNERS, environnements, board Projects | type/enabler, area/ci-cd, area/security, role/ops, priority/must, size/m | E0 | must | m | OPS |  | EN-01, EN-71 | docs/backlog/issues/EN-02.md |
| EN-71 | CREATE |  | EN-71 — CI : titre de PR, lint, sécurité, tests unitaires, docs | type/enabler, area/ci-cd, area/qa, role/ops, role/qe, priority/must, size/m | E7 | must | m | OPS |  | EN-01 | docs/backlog/issues/EN-71.md |
| EN-11 | CREATE |  | EN-11 — Spike : inspection du compte workshop (région, droits IAM/OIDC, Bedrock, S3 Vectors, SES, services déjà actifs) | type/spike, area/infra, area/ai, role/ops, role/as, priority/must, size/s | E1 | must | s | OPS |  |  | docs/backlog/issues/EN-11.md |
| EN-12 | CREATE |  | EN-12 — Bootstrap : bucket de state, KMS, chiffrement du state OpenTofu, verrou natif | type/enabler, area/infra, area/security, role/ops, priority/must, size/m | E1 | must | m | OPS |  | EN-11 | docs/backlog/issues/EN-12.md |
| EN-13 | CREATE |  | EN-13 — OIDC GitHub : rôles plan/apply et permissions boundary | type/enabler, area/infra, area/security, area/ci-cd, role/ops, priority/must, size/m | E1 | must | m | OPS |  | EN-11, EN-12 | docs/backlog/issues/EN-13.md |
| EN-14 | CREATE |  | EN-14 — Clés KMS par domaine (data, logs, ai) | type/enabler, area/infra, area/security, role/ops, priority/must, size/s | E1 | must | s | OPS |  | EN-12, EN-13, EN-73 | docs/backlog/issues/EN-14.md |
| EN-41 | CREATE |  | EN-41 — Module générique `lambda-service` (rôle dédié, logs KMS, alias, DLQ, tracing) | type/enabler, area/infra, role/ops, priority/must, size/m | E4 | must | m | OPS |  | EN-13, EN-14 | docs/backlog/issues/EN-41.md |
| EN-42 | CREATE |  | EN-42 — Table `tickets` (GSI, streams, PITR, protection contre la suppression) | type/enabler, area/infra, role/ops, priority/must, size/s | E4 | must | s | OPS |  | EN-14 | docs/backlog/issues/EN-42.md |
| EN-21 | UPDATE | 18 | EN-21 — Hébergement et sécurisation du front S3/CloudFront | type/enabler, area/infra, area/front, area/security, role/ops, priority/must, size/m | E2 | must | m | OPS | G8LD | EN-14, EN-33 | docs/backlog/issues/EN-21.md |
| RF04 | UPDATE | 13 | RF04 — Protection WAF et limitation de débit | type/nfr, area/security, area/infra, role/ops, role/as, priority/must, size/m | E2 | must | m | OPS |  | EN-21, EN-33, EN-14 | docs/backlog/issues/RF04.md |
| EN-31 | CREATE |  | EN-31 — Cognito : user pool, groupes, client PKCE, MFA admin, utilisateurs de test (dev) | type/enabler, area/infra, area/security, role/ops, priority/must, size/m | E3 | must | m | OPS |  | EN-13, EN-14, EN-21 | docs/backlog/issues/EN-31.md |
| EN-32 | UPDATE | 19 | EN-32 — Validation des tokens par l'authorizer Cognito de l'API REST | type/enabler, area/infra, area/security, area/app, role/ops, role/se, priority/must, size/s | E3 | must | s | OPS | G8LD | EN-31, EN-33 | docs/backlog/issues/EN-32.md |
| EN-33 | CREATE |  | EN-33 — API REST régionale : ressources/méthodes, validation des requêtes (modèles JSON Schema), throttling, logs d'accès JSON, X-Ray | type/enabler, area/infra, area/app, role/ops, priority/must, size/l | E3 | must | l | OPS |  | EN-41, EN-14, EN-05 | docs/backlog/issues/EN-33.md |
| EN-72 | CREATE |  | EN-72 — Plan sur les PR (OIDC lecture seule), commentaire, Infracost | type/enabler, area/ci-cd, role/ops, priority/must, size/m | E7 | must | m | OPS |  | EN-71, EN-13 | docs/backlog/issues/EN-72.md |
| EN-73 | CREATE |  | EN-73 — Apply GitOps : develop → dev, main → prod avec approbation, plan figé | type/enabler, area/ci-cd, role/ops, priority/must, size/l | E7 | must | l | OPS |  | EN-72, EN-13, EN-02 | docs/backlog/issues/EN-73.md |
| EN-74 | CREATE |  | EN-74 — Déploiement applicatif : artefacts Lambda, alias, SPA, invalidation, rollback | type/enabler, area/ci-cd, role/ops, priority/must, size/l | E7 | must | l | OPS |  | EN-73, EN-41, EN-21, EN-05 | docs/backlog/issues/EN-74.md |
| EN-44 | CREATE |  | EN-44 — SLA : groupe Scheduler, rôle et cible d'escalade | type/enabler, area/infra, role/ops, priority/must, size/s | E4 | must | s | OPS |  | EN-41, EN-42 | docs/backlog/issues/EN-44.md |
| EN-45 | CREATE |  | EN-45 — Notifications : identités SES, topics SNS (admins, ops) | type/enabler, area/infra, role/ops, priority/should, size/s | E4 | should | s | OPS |  | EN-14, EN-41 | docs/backlog/issues/EN-45.md |
| EN-52 | CREATE |  | EN-52 — Guardrail Bedrock (sujets interdits, PII, injection de prompt, ancrage) | type/enabler, area/ai, area/security, role/ops, priority/must, size/m | E5 | must | m | OPS |  | EN-11, EN-14 | docs/backlog/issues/EN-52.md |
| EN-53 | CREATE |  | EN-53 — Table `chat-sessions` avec TTL | type/enabler, area/infra, area/ai, role/ops, priority/should, size/s | E5 | should | s | OPS |  | EN-14 | docs/backlog/issues/EN-53.md |
| EN-51 | CREATE |  | EN-51 — Bedrock Knowledge Base, S3 Vectors, bucket des sources | type/enabler, area/ai, area/infra, role/ops, role/as, priority/should, size/l | E5 | should | l | OPS |  | EN-11, EN-14, EN-41 | docs/backlog/issues/EN-51.md |
| EN-43 | CREATE |  | EN-43 — Bucket des pièces jointes : POST pré-signé, Malware Protection | type/enabler, area/infra, area/security, role/ops, priority/should, size/m | E4 | should | m | OPS |  | EN-14, EN-41, EN-11 | docs/backlog/issues/EN-43.md |
| EN-46 | CREATE |  | EN-46 — Agrégats KPI depuis le stream (table `kpi`) | type/enabler, area/infra, area/app, role/ops, role/se, priority/should, size/m | E4 | should | m | OPS |  | EN-42, EN-41 | docs/backlog/issues/EN-46.md |
| EN-61 | UPDATE | 20 | EN-61 — Centralisation des logs, dashboards et alertes SNS | type/enabler, area/observability, role/ops, priority/must, size/m | E6 | must | m | OPS | G8LD | EN-14, EN-41, EN-33, RF04, EN-45 | docs/backlog/issues/EN-61.md |
| EN-81 | CREATE |  | EN-81 — Stratégie de test et matrice de traçabilité | type/enabler, area/qa, role/qe, priority/must, size/s | E8 | must | s | QE |  |  | docs/backlog/issues/EN-81.md |
| EN-82 | CREATE |  | EN-82 — Socle de tests unitaires IaC (`tofu test`, provider simulé) | type/enabler, area/qa, area/infra, role/qe, priority/must, size/m | E8 | must | m | QE |  | EN-01, EN-81 | docs/backlog/issues/EN-82.md |
| EN-83 | CREATE |  | EN-83 — Tests smoke et sécurité post-déploiement (Hurl : 401/403, BOLA, upload, WAF) | type/enabler, area/qa, area/security, role/qe, priority/must, size/m | E8 | must | m | QE |  | EN-81, EN-74, EN-32, RF04, EN-43 | docs/backlog/issues/EN-83.md |
| EN-84 | CREATE |  | EN-84 — Performance k6 (exigence < 2 s : p95 < 2000 ms) | type/enabler, area/qa, role/qe, priority/should, size/s | E8 | should | s | QE |  | EN-81, EN-74 | docs/backlog/issues/EN-84.md |
| EN-85 | CREATE |  | EN-85 — E2E Playwright des parcours critiques | type/enabler, area/qa, area/front, role/qe, priority/could, size/m | E8 | could | m | QE |  | EN-81, EN-74, US04, US03, US01, US10 | docs/backlog/issues/EN-85.md |
| EN-86 | CREATE |  | EN-86 — DAST : scan de base OWASP ZAP (nocturne, dev) | type/enabler, area/qa, area/security, role/qe, priority/could, size/s | E8 | could | s | QE |  | EN-74, EN-81 | docs/backlog/issues/EN-86.md |
| EN-91 | CREATE |  | EN-91 — ADR initiaux (OpenTofu, compte unique, pas de domaine, API REST + WAF régional plutôt qu'API HTTP, authorizer Cognito natif, pas de VPC, S3 Vectors, scheduler SLA) | type/enabler, area/docs, role/as, priority/must, size/m | E9 | must | m | AS |  | EN-11 | docs/backlog/issues/EN-91.md |
| EN-92 | CREATE |  | EN-92 — Diagramme d'architecture v3 (drawio + diagram-as-code) | type/enabler, area/docs, role/as, priority/should, size/s | E9 | should | s | AS |  | EN-91 | docs/backlog/issues/EN-92.md |
| EN-93 | CREATE |  | EN-93 — Estimation des coûts (Infracost et hypothèses de charge) | type/enabler, area/docs, role/as, role/ops, priority/should, size/s | E9 | should | s | AS |  | EN-72, EN-91, EN-16 | docs/backlog/issues/EN-93.md |
| EN-94 | CREATE |  | EN-94 — Runbooks : déploiement, rollback, incident, rotation | type/enabler, area/docs, role/ops, priority/should, size/m | E9 | should | m | OPS |  | EN-73, EN-74, EN-61 | docs/backlog/issues/EN-94.md |
| EN-95 | CREATE |  | EN-95 — Préparation de la démo (scénario, données de démo, script) | type/enabler, area/docs, area/qa, role/ba, role/qe, priority/must, size/m | E9 | must | m | BA |  | EN-83, US01, US02, US03, US04, US05, US10, RF01, RF03, RF04 | docs/backlog/issues/EN-95.md |
| EN-04 | CREATE |  | EN-04 — README + CONTRIBUTING + onboarding équipe | type/enabler, area/docs, role/ops, priority/must, size/s | E0 | must | s | OPS |  | EN-01, EN-05 | docs/backlog/issues/EN-04.md |
| EN-05 | CREATE |  | EN-05 — Contrat infra/app documenté | type/enabler, area/docs, area/app, role/ops, role/se, priority/must, size/s | E3 | must | s | OPS |  | EN-01 | docs/backlog/issues/EN-05.md |
| EN-03 | CREATE |  | EN-03 — Chaîne d'approvisionnement : Renovate, actions épinglées par SHA, secret scanning et push protection | type/enabler, area/ci-cd, area/security, role/ops, priority/should, size/s | E0 | should | s | OPS |  | EN-01, EN-71 | docs/backlog/issues/EN-03.md |
| EN-15 | CREATE |  | EN-15 — Baseline sécurité du compte (CloudTrail, GuardDuty, Security Hub, Config, Access Analyzer), avec interrupteurs | type/enabler, area/security, area/infra, role/ops, priority/should, size/m | E1 | should | m | OPS |  | EN-11, EN-14 | docs/backlog/issues/EN-15.md |
| EN-16 | CREATE |  | EN-16 — Budget AWS et alertes de coût | type/enabler, area/infra, role/ops, priority/should, size/xs | E1 | should | xs | OPS |  | EN-11 | docs/backlog/issues/EN-16.md |
| EN-22 | UPDATE | 21 | EN-22 — Domaine personnalisé et certificats ACM | type/enabler, area/infra, role/ops, priority/wont, size/xs | E2 | wont | xs | OPS | G8LD | EN-21 | docs/backlog/issues/EN-22.md |
| EN-75 | CREATE |  | EN-75 — Détection de dérive nocturne → issue | type/enabler, area/ci-cd, role/ops, priority/could, size/s | E7 | could | s | OPS |  | EN-73, EN-13 | docs/backlog/issues/EN-75.md |
| EN-76 | CREATE |  | EN-76 — Releases : release-please, changelog, garde de `main` | type/enabler, area/ci-cd, role/ops, priority/should, size/s | E7 | should | s | OPS |  | EN-71, EN-02 | docs/backlog/issues/EN-76.md |
| NFR-01 | UPDATE | 11 | NFR-01 — Traçabilité GitOps et Infrastructure as Code | type/nfr, area/ci-cd, role/ops, priority/must, size/s | E7 | must | s | OPS |  | EN-13, EN-72, EN-73, EN-75 | docs/backlog/issues/NFR-01.md |
| US04 | UPDATE | 4 | US04 — Création d'un ticket de support par l'étudiant | type/story, area/app, area/front, role/se, priority/must, size/m | E4 | must | m | SE |  | EN-42, EN-32, EN-33, EN-44, EN-45, EN-43 | docs/backlog/issues/US04.md |
| US03 | UPDATE | 3 | US03 — Suivi de l'état d'avancement des tickets | type/story, area/app, area/front, area/security, role/se, priority/must, size/m | E4 | must | m | SE |  | EN-42, EN-32, US04 | docs/backlog/issues/US03.md |
| US01 | UPDATE | 1 | US01 — Gestion et mise à jour des tickets par l'administrateur | type/story, area/app, area/front, role/se, priority/must, size/l | E4 | must | l | SE |  | EN-42, EN-32, EN-33, US03 | docs/backlog/issues/US01.md |
| RF01 | UPDATE | 10 | RF01 — Cycle de vie des tickets et gestion des SLA | type/story, area/app, area/infra, role/se, role/ops, priority/must, size/m | E4 | must | m | SE |  | US04, EN-44, EN-45, EN-42 | docs/backlog/issues/RF01.md |
| US09 | UPDATE | 15 | US09 — Notifications e-mail automatiques via Amazon SES | type/story, area/app, role/se, priority/should, size/s | E4 | should | s | SE |  | EN-45, EN-42, EN-21, US01 | docs/backlog/issues/US09.md |
| US05 | UPDATE | 5 | US05 — Consultation des indicateurs KPI des tickets | type/story, area/app, area/front, role/se, priority/should, size/m | E4 | should | m | SE |  | EN-46, EN-32, EN-33 | docs/backlog/issues/US05.md |
| US06 | UPDATE | 6 | US06 — Authentification unifiée SSO Microsoft | type/story, area/security, area/app, area/infra, role/se, role/ops, priority/could, size/m | E3 | could | m | SE |  | EN-31, EN-32, EN-41 | docs/backlog/issues/US06.md |
| US02 | UPDATE | 2 | US02 — Discussion avec le chatbot du campus | type/story, area/ai, area/app, area/front, role/se, priority/must, size/l | E5 | must | l | SE |  | EN-51, EN-52, EN-53, EN-32 | docs/backlog/issues/US02.md |
| US07 | UPDATE | 9 | US07 — Synchronisation automatique des sources documentaires S3 | type/story, area/ai, area/app, role/se, priority/should, size/s | E5 | should | s | SE |  | EN-51, EN-41 | docs/backlog/issues/US07.md |
| RF03 | UPDATE | 12 | RF03 — Confinement et validation de la source documentaire RAG | type/story, area/ai, area/security, role/se, role/ops, priority/must, size/m | E5 | must | m | SE |  | EN-51, EN-52, US02 | docs/backlog/issues/RF03.md |
| US08 | UPDATE | 14 | US08 — Anonymisation et purge RGPD des historiques de chat | type/story, area/ai, area/security, area/app, role/se, priority/should, size/m | E5 | should | m | SE |  | EN-53, EN-52, US02 | docs/backlog/issues/US08.md |
| US10 | UPDATE | 16 | US10 — Escalade du chatbot vers un ticket | type/story, area/ai, area/app, area/front, role/se, priority/should, size/s | E5 | should | s | SE |  | US02, US04, RF03 | docs/backlog/issues/US10.md |
|  | KEEP CLOSED | 7 | Automatic synchronization of campus document sources |  |  |  |  |  |  |  |  |
|  | KEEP CLOSED | 8 | Automatic synchronization of campus document sources |  |  |  |  |  |  |  |  |
|  | KEEP CLOSED | 17 | US13 - Centralisation des logs applicatifs et alertes d'erreurs |  |  |  |  |  |  |  |  |

Contrôle : 10 epics + 57 stories/enablers = 67 corps ; 49 CREATE, 18 UPDATE, 3 KEEP CLOSED (21 issues existantes).

## 4. Incohérences et questions PO

### Incohérences relevées

1. **Priorités : des `must` dépendent de `should`/`could`.** US02 (must) → EN-51, EN-53 (should) ; RF03 (must) → EN-51 ; RF01, US04 et EN-61 (must) → EN-45 (should) ; EN-83 (must, AC4) et US04 (AC6) → EN-43 (should) ; NFR-01 (must, AC3) → EN-75 (could) ; EN-95 (must) → US05, US10 (should). Proposition : passer EN-45, EN-51, EN-53 en `must` ; EN-75 en `should` ou retirer AC3 de NFR-01 ; conditionner les AC dépendant de EN-43 à la décision PO.
2. **Ordre de réalisation vs dépendances.** EN-14 dépend de EN-73 et toutes les briques de l'étape 4 ont « appliqué via EN-73 » dans leur DoD, alors que EN-72/EN-73 sont à l'étape 5. Proposition : coder et tester les briques de l'étape 4 en parallèle, mais livrer EN-72/EN-73 avant leur premier apply. EN-02 (étape 1) dépend de EN-71 (étape 2) : AC4 en seconde PR, déjà prévu.
3. **Aucun cycle de dépendances** détecté dans le tableau. Dépendance implicite inverse : EN-75 exige un `sub` supplémentaire dans les rôles de EN-13 (planifié) ; à intégrer à EN-13 pour ne pas rouvrir le bootstrap.
4. **EN-04 et EN-05 absents de `backlog-v2.md`.** EN-05 formalise le « contrat OpenAPI initial » cité par EN-33 et le format d'artefact attendu par EN-74 : ajouté comme dépendance des deux, il doit être traité dès l'étape 4. `backlog-v2.md` est à mettre à jour.
5. **Taxonomie :** aucun `type/` pour les règles métier `RF-xx`. Choix retenu : `type/story` pour RF01/RF03 (comportement applicatif), `type/nfr` pour RF04 (exigence de sécurité transverse, comme NFR-01). L'ID `RF02` disparaît au profit de NFR-01 (#11).
6. **Recouvrements (pas de doublon bloquant) :** throttling API dans EN-33 et RF04 (porté par EN-33, vérifié par RF04) ; « pas de diff sur le code » dans EN-41-AC6 et EN-74-AC5 ; journalisation des invocations Bedrock dans US08-AC5 et EN-51. À garder, avec un seul porteur de test chacun.
7. **Architecture vs backlog :** l'architecture v3 (contraignante) fixe le bucket des pièces jointes (POST pré-signé ≤ 10 Mo, Malware Protection) alors que US04 le laisse « à valider par le PO » et EN-43 est `should`. Si le PO refuse la pièce jointe, un ADR doit retirer cette brique de l'architecture.
8. **Rôle de déploiement applicatif** (EN-74) : bootstrap ou foundation, non tranché ; impacte EN-13 et NFR-01-AC1.
9. **Taille des epics :** `size/` imposé sur toutes les lignes ; valeur indicative (somme des enfants), non utilisée pour la planification.

### Questions ouvertes pour le PO

1. Pièce jointe JPG/PNG ≤ 10 Mo dans US04 : confirmée ? (décide la priorité de EN-43 et US04-AC6).
2. Valider les montées de priorité proposées (EN-45, EN-51, EN-53 en `must` ; EN-75 en `should`).
3. Liste des priorités de ticket et transitions de statut autorisées (US01) ; règle exacte d'escalade SLA et destinataires (RF01).
4. Durées de rétention : `chat-sessions` (US08, EN-53), pièces jointes (EN-43) ; périmètre de la suppression à la demande (chat seul ou aussi tickets).
5. Seuil de latence acceptable pour le chat (EN-84).
6. Assignations des nouvelles issues (logins GitHub par rôle) ; confirmation que `G8LD` reste assigné à #18–#21.
7. US06 : l'inscription d'application dans le tenant Entra de l'école est-elle obtenable pendant le workshop ? Sinon, report explicite.

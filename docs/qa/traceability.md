# Matrice de traçabilité (EN-81)

Exigence → critère d'acceptation (AC) → test → outil → étape. Source des exigences : `docs/backlog/backlog-v2.md`. Stratégie : [`test-strategy.md`](test-strategy.md).

**Statut des AC : à synchroniser avec les issues.** Les AC ci-dessous sont dérivés à un niveau macro ; leur numérotation peut changer.

## Conventions

- ID de test : `SMK-nnn`, `SEC-nnn`, `PERF-nnn`, `E2E-nnn`, `DAST-nnn`, `UNIT-<module>-nnn`, `INT-<module>-nnn`, `SVC-<function>-nnn` (SE).
- Nom du test : `<Exigence>-AC<n> <comportement>` (ex. `US03-AC3 student cannot read another student's ticket`).
- Étapes : S1 pré-commit, S2 CI de PR, S3 post-déploiement dev, S4 nocturne, S5 gate prod (voir la stratégie).
- Statut : `Planifié` → `Écrit` → `Passant` / `En échec`. Tout est `Planifié` à ce stade.
- Un test listé sur plusieurs AC n'est écrit qu'une fois.

## Fonctionnel

| Exigence | AC | Test ID | Intitulé | Outil | Étape | Statut |
|---|---|---|---|---|---|---|
| US01 | AC1 admin liste et filtre les tickets | SMK-006 | admin lists and filters tickets | Hurl | S3 | Planifié |
| US01 | AC2 changement de statut avec événement d'audit (horodatage, id admin) | SMK-007 | status change writes audit event | Hurl | S3 | Planifié |
| US01 | AC3 clôture impossible sans note de résolution | SMK-008 | closing without resolution note rejected | Hurl | S3 | Planifié |
| US01 | AC4 priorité dont `critique` | SMK-009 | admin sets priority including critique | Hurl | S3 | Planifié |
| US01 | AC5 réservé au groupe admin | SEC-004 | student on admin route gets 403 | Hurl | S3, S5 | Planifié |
| US01 | parcours admin | E2E-002 | admin processes a ticket to resolved | Playwright | S3 | Planifié |
| US02 | AC1 réponse issue de la KB uniquement | SMK-011 | in-scope question gets grounded answer | Hurl | S3 | Planifié |
| US02 | AC2 historique stocké avec TTL | UNIT-data-003 | chat-sessions has TTL attribute enabled | tofu test | S2 | Planifié |
| US03 | AC1 l'étudiant liste ses tickets | SMK-004 | student lists own tickets | Hurl | S3 | Planifié |
| US03 | AC2 statuts autorisés (Ouvert, En cours, En attente étudiant, Résolu, Fermé) | SMK-005 | ticket detail exposes allowed status values | Hurl | S3 | Planifié |
| US03 | AC3 **BOLA** : l'étudiant ne voit que ses tickets | SEC-005 | student A cannot read student B ticket (403/404) | Hurl | S3, S5 | Planifié |
| US03 | AC3 **BOLA** (écriture) | SEC-006 | student A cannot update student B ticket (403/404) | Hurl | S3, S5 | Planifié |
| US03 | AC3 identité issue du `sub` | SEC-019 | owner id in request body is ignored | Hurl | S3, S5 | Planifié |
| US03 | parcours étudiant | E2E-001 | student logs in, creates and sees own ticket | Playwright | S3 | Planifié |
| US04 | AC1 création, statut initial « Ouvert » | SMK-001 | create ticket returns 201 with status Ouvert | Hurl | S3 | Planifié |
| US04 | AC2 titre obligatoire | SMK-002 | rejects ticket without title | Hurl | S3 | Planifié |
| US04 | AC3 catégorie sécurité ⇒ `critique` + alerte | SMK-003 | security category sets priority critique | Hurl | S3 | Planifié |
| US04 | AC3 alerte admins | UNIT-notifications-002 | admin alert topic exists with encryption | tofu test | S2 | Planifié |
| US04 | AC4 pièce jointe JPG/PNG ≤ 10 Mo (PO à valider) | SMK-020 | presigned POST issued for valid image | Hurl | S3 | Planifié |
| US04 | AC5 refus > 10 Mo | SEC-007 | upload above 10 MB rejected | Hurl | S3, S5 | Planifié |
| US04 | AC5 refus type non image | SEC-008 | non-image content type rejected | Hurl | S3, S5 | Planifié |
| US04 | politique de bucket | UNIT-data-004 | attachments bucket private, SSE-KMS, TLS-only | tofu test | S2 | Planifié |
| US05 | AC1 KPI par statut et catégorie | SMK-010 | admin reads KPI aggregates | Hurl | S3 | Planifié |
| US05 | AC2 lecture depuis la table `kpi` | SVC-kpi-001 | kpi reads daily aggregates, no ticket query | unitaire SE | S2 | Planifié |
| US05 | AC3 réservé aux admins | SEC-016 | student on KPI route gets 403 | Hurl | S3, S5 | Planifié |
| US06 | AC1 connexion Entra (si activée) | E2E-004 | Entra sign-in when enable_entra_federation=true | Playwright | S3 (conditionnel) | Planifié |
| US06 | AC2 filtrage du domaine e-mail | SVC-pre-token-001 | pre-token rejects unapproved domain | unitaire SE | S2 | Planifié |
| US06 | AC3 repli sur utilisateurs Cognito natifs | UNIT-identity-003 | federation disabled by default | tofu test | S2 | Planifié |
| US07 | AC1 événement S3 → ingestion | INT-ai-001 | source upload starts ingestion job | tofu test | S4 | Planifié |
| US07 | AC2 journal succès/échec | SVC-kb-sync-001 | ingestion status is logged | unitaire SE | S2 | Planifié |
| US08 | AC1 TTL de purge | UNIT-data-003 | chat-sessions has TTL attribute enabled | tofu test | S2 | Planifié |
| US08 | AC2 suppression à la demande | SMK-013 | user data deletion on request | Hurl | S3 | Planifié |
| US08 | AC3 PII masquées | SEC-018 | PII in chat is masked by guardrail | Hurl | S3 | Planifié |
| US08 | AC4 invocations Bedrock non conservées ou rétention courte | UNIT-ai-003 | model invocation logging off or short retention | tofu test | S2 | Planifié |
| US09 | AC1 e-mail au changement de statut | SVC-notifier-001 | status change triggers email | unitaire SE | S2 | Planifié |
| US09 | AC2 lien vers l'URL CloudFront | SVC-notifier-002 | email link uses CloudFront URL | unitaire SE | S2 | Planifié |
| US09 | AC3 identités SES vérifiées (sandbox) | UNIT-notifications-001 | SES identities declared | tofu test | S2 | Planifié |
| US10 | AC1 escalade chat → ticket | SMK-012 | escalation from chat creates ticket | Hurl | S3 | Planifié |
| US10 | AC2 contexte pré-remplit le ticket | E2E-003 | out-of-scope chat escalates with prefilled form | Playwright | S3 | Planifié |
| RF01 | AC1 statut initial « Ouvert » | SMK-001 | (voir US04-AC1) | Hurl | S3 | Planifié |
| RF01 | AC2 rendez-vous unique à +24 h | UNIT-scheduler-001 | schedule group, role and target declared | tofu test | S2 | Planifié |
| RF01 | AC2 rendez-vous créé à la création | SVC-tickets-001 | creation registers one-time at(created+24h) schedule | unitaire SE | S2 | Planifié |
| RF01 | AC3 escalade idempotente | SVC-escalation-001 | escalation is no-op if ticket left Ouvert | unitaire SE | S2 | Planifié |
| RF01 | AC3 bout en bout | INT-scheduler-001 | schedule fires escalation once | tofu test | S4 | Planifié |
| RF03 | AC1 réponse ancrée dans le périmètre | SMK-011 | (voir US02-AC1) | Hurl | S3 | Planifié |
| RF03 | AC2 **refus ancré** sous le seuil + offre de ticket | SEC-012 | out-of-scope question gets refusal and ticket offer | Hurl | S3, S5 | Planifié |
| RF03 | AC2 seuil de l'ancrage contextuel | UNIT-ai-001 | guardrail has contextual grounding thresholds | tofu test | S2 | Planifié |
| RF03 | AC3 injection de prompt | SEC-013 | prompt attack is blocked | Hurl | S3 | Planifié |
| RF03 | AC2 parcours | E2E-003 | (voir US10-AC2) | Playwright | S3 | Planifié |

## Réseau, sécurité, plateforme

| Exigence | AC | Test ID | Intitulé | Outil | Étape | Statut |
|---|---|---|---|---|---|---|
| RF04 | AC1 deux web ACL (CloudFront, régionale API) | UNIT-waf-001 | CLOUDFRONT and REGIONAL web ACLs declared | tofu test | S2 | Planifié |
| RF04 | AC1 groupes managés + limite de corps | UNIT-waf-002 | managed rule groups and body size limit present | tofu test | S2 | Planifié |
| RF04 | AC2 **limite de débit** via CloudFront | SEC-009 | burst above rate limit gets 429/403 | Hurl | S3, S5 | Planifié |
| RF04 | AC2 **limite de débit** en direct `execute-api` | SEC-010 | burst on execute-api URL gets 429/403 | Hurl | S3, S5 | Planifié |
| RF04 | AC2 règles par `Authorization` et par IP | UNIT-waf-003 | rate rules keyed on Authorization header and IP | tofu test | S2 | Planifié |
| RF04 | AC3 charge utile malveillante bloquée | SEC-011 | known-bad payload blocked | Hurl | S3, S5 | Planifié |
| RF04 | AC4 throttling stage/méthode | UNIT-api-003 | stage and method throttling configured | tofu test | S2 | Planifié |
| NFR-01 | AC1 aucun apply hors CI (sauf bootstrap) | CI-lint-001 | workflows lint clean and apply only via approved workflow | actionlint, zizmor | S2 | Planifié |
| NFR-01 | AC2 détection de dérive (EN-75, could) | INT-drift-001 | nightly plan reports no drift | tofu plan | S4 | Planifié |
| NFR-01 | AC3 traçabilité issue ↔ PR ↔ déploiement | CI-pr-001 | PR title is conventional and body has `Closes #n` | CI | S2 | Planifié |
| NFR-PERF (provisoire) | AC1 p95 < 2000 ms, échecs < 1 % : liste de tickets | PERF-001 | list tickets under threshold | k6 | S3 | Planifié |
| NFR-PERF | AC1 création de ticket | PERF-002 | create ticket under threshold | k6 | S3 | Planifié |
| NFR-PERF | AC1 chat | PERF-003 | chat answer under threshold | k6 | S3 | Planifié |
| NFR-PERF | AC1 KPI | PERF-004 | KPI read under threshold | k6 | S3 | Planifié |
| EN-21 | AC1 redirection HTTP → HTTPS | SEC-014 | HTTP request redirected to HTTPS | Hurl | S3, S5 | Planifié |
| EN-21 | AC2 en-têtes HSTS, CSP, nosniff, Referrer-Policy | SEC-015 | security headers present | Hurl | S3, S5 | Planifié |
| EN-21 | AC3 TLS 1.2 minimum | UNIT-edge-002 | minimum TLS protocol is TLSv1.2_2021 | tofu test | S2 | Planifié |
| EN-21 | AC4 `/api/*` vers l'API, sans cache | UNIT-edge-003 | api behaviour has caching disabled and forwards Authorization | tofu test | S2 | Planifié |
| EN-21 | AC5 bucket SPA privé (OAC) | SEC-017 | direct S3 access to SPA bucket denied | Hurl | S3 | Planifié |
| EN-21 | AC5 Block Public Access | UNIT-edge-001 | SPA bucket blocks public access | tofu test | S2 | Planifié |
| EN-32 | AC1 **sans token → 401** | SEC-001 | request without token gets 401 | Hurl | S3, S5 | Planifié |
| EN-32 | AC2 token invalide → 401 | SEC-002 | invalid token gets 401 | Hurl | S3, S5 | Planifié |
| EN-32 | AC2 token expiré → 401 | SEC-003 | expired token gets 401 | Hurl | S3, S5 | Planifié |
| EN-32 | AC3 groupes lus depuis `cognito:groups` | SEC-004 | (voir US01-AC5) | Hurl | S3, S5 | Planifié |
| EN-32 | AC4 authorizer Cognito natif, pas de Lambda authorizer | UNIT-api-001 | methods use COGNITO_USER_POOLS authorizer | tofu test | S2 | Planifié |
| EN-33 | AC1 validation des requêtes (JSON Schema) | SMK-014 | invalid body gets 400 | Hurl | S3 | Planifié |
| EN-33 | AC2 API REST régionale | UNIT-api-002 | REST API endpoint type is REGIONAL | tofu test | S2 | Planifié |
| EN-31 | AC1 PKCE seul, pas de secret client | UNIT-identity-001 | app client has no secret and uses code flow | tofu test | S2 | Planifié |
| EN-31 | AC2 MFA exigée pour admin | UNIT-identity-002 | MFA required for admin | tofu test | S2 | Planifié |
| EN-14 | AC1 clés KMS avec rotation | UNIT-kms-001 | CMKs have rotation enabled | tofu test | S2 | Planifié |
| EN-41 | AC1 un rôle par fonction, logs KMS, DLQ | UNIT-lambda-service-001 | role, log group and DLQ declared per function | tofu test | S2 | Planifié |
| EN-42 | AC1 table `tickets` : PITR, GSI, stream | UNIT-data-001 | tickets table has PITR, GSIs and stream | tofu test | S2 | Planifié |
| EN-44 | AC1 groupe Scheduler et cible d'escalade | UNIT-scheduler-001 | (voir RF01-AC2) | tofu test | S2 | Planifié |
| EN-52 | AC1 Guardrail : sujets, PII, attaque de prompt, ancrage | UNIT-ai-002 | guardrail filters declared | tofu test | S2 | Planifié |
| EN-61 | AC1 alarmes 5xx, p95, DLQ, WAF → SNS | UNIT-observability-001 | alarms wired to SNS topic | tofu test | S2 | Planifié |
| EN-86 | AC1 scan ZAP de base | DAST-001 | ZAP baseline on CloudFront URL | OWASP ZAP | S4 | Planifié |

## Lacunes connues

- AC à synchroniser avec les issues ; les numéros peuvent bouger.
- `NFR-PERF` n'a pas d'ID dans le backlog ; `CI-*` sont des contrôles de CI, pas des tests Hurl ou `tofu test`.
- Tests applicatifs `SVC-*` : portés par SE, noms de fonctions repris de l'architecture.
- Pas de test couvrant US06-AC1 si la fédération reste désactivée (cas conditionnel).
- EN-22 (domaine, statut « won't ») : volontairement non couvert.

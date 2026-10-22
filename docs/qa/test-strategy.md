# Stratégie de test (EN-81)

Périmètre : SmartCampus AI, plateforme serverless `eu-west-3` (architecture v3). Propriétaire du document : QE. Matrice de couverture : [`traceability.md`](traceability.md).

## 1. Principes

- Un test vérifie un critère d'acceptation (AC) et porte son identifiant : `US04-AC2 rejects ticket without title`.
- Déterministe et idempotent : chaque test crée et nettoie ses données (préfixe `qa-<run-id>`).
- Les tests de sécurité obligatoires (section 8) ne sont jamais optionnels et bloquent la promotion.
- Les AC sont dérivés de `docs/backlog/backlog-v2.md` à un niveau macro. **À synchroniser avec les issues** avant de figer les tests.

## 2. Pyramide

| Niveau | Outil | Emplacement | Préfixe d'ID |
|---|---|---|---|
| Statique | `tofu fmt/validate`, tflint, actionlint, zizmor | dépôt | n/a |
| Politiques | Checkov (+ `policies/`), Trivy config, gitleaks | dépôt | n/a |
| Unitaire IaC | `tofu test` + `mock_provider`, `command = plan` | `infra/modules/<module>/tests/unit.tftest.hcl` | `UNIT-<module>-nnn` |
| Intégration IaC | `tofu test`, `command = apply`, ressources éphémères | `infra/modules/<module>/tests/integration.tftest.hcl` | `INT-<module>-nnn` |
| Unitaire applicatif | runtime choisi par SE | `services/<function>/` | `SVC-<function>-nnn` (SE) |
| Contrat + smoke | Hurl, OpenAPI de `packages/contracts` | `tests/smoke` | `SMK-nnn` |
| Sécurité | Hurl | `tests/security` | `SEC-nnn` |
| Performance | k6, seuils `p(95)<2000` et `http_req_failed<1%` | `tests/perf` | `PERF-nnn` |
| E2E | Playwright, parcours critiques uniquement | `tests/e2e` | `E2E-nnn` |
| DAST | OWASP ZAP baseline sur l'URL CloudFront | CI | `DAST-nnn` |

Les modules IaC cités dans la matrice (`edge`, `waf`, `identity`, `api`, `data`, `lambda-service`, `scheduler`, `ai`, `notifications`, `observability`, `kms`) sont provisoires : ils seront alignés sur `infra/modules/` quand il existera.

## 3. Quoi tourne où

| Étape | Déclencheur | Contenu | Bloquant |
|---|---|---|---|
| S1 pré-commit / pré-push | poste dev | fmt, lint, gitleaks, Checkov | oui (local) |
| S2 CI de PR | chaque PR | statique, politiques, `UNIT-*`, `SVC-*`, plan en lecture seule | oui (checks requis) |
| S3 post-déploiement dev | après apply sur `develop` | `SMK-*`, `SEC-*`, `PERF-*`, `E2E-*` | oui pour la release |
| S4 nocturne dev | planifié | `INT-*`, `DAST-*`, rejeu complet `SEC-*` | non, ouvre une issue |
| S5 gate prod | PR `develop` → `main` | `SMK-*` et `SEC-*` verts sur la dernière version dev | oui |

Les tests de débit WAF (`SEC-009`, `SEC-010`) tournent sur dev uniquement.

## 4. Critères d'entrée et de sortie

Entrée (démarrer l'écriture ou l'exécution) :
- l'issue a des AC numérotés et un contrat (`packages/contracts`) à jour ;
- pour S3 : déploiement dev réussi, utilisateurs de test présents (`enable_test_users`) ;
- pour S2 : toolchain épinglée installée.

Sortie (considérer le test ou la livraison comme terminé) :
- chaque AC `must` a au moins un test dans la matrice, statut « Passant » ;
- les cas de sécurité obligatoires sont verts ;
- performance : `p(95) < 2000 ms` et taux d'échec `< 1 %` ;
- aucune anomalie ouverte de sévérité critique ou majeure ;
- `traceability.md` mis à jour dans la même PR.

## 5. Environnements

| Env | Usage des tests | Remarque |
|---|---|---|
| local / CI | S1, S2 | provider simulé, aucun accès AWS pour `UNIT-*` |
| dev (`sc-dev`) | S3, S4 | cible de `SMK`, `SEC`, `PERF`, `E2E`, `INT`, `DAST` |
| prod (`sc-prod`) | S5 uniquement comme gate indirect | pas de test de charge ni de débit WAF |

Les tests visent l'URL `*.cloudfront.net` (point d'entrée utilisateur). Les tests WAF vérifient aussi l'URL `execute-api` directe, car elle reste joignable (pas de domaine personnalisé).

## 6. Données de test

- Utilisateurs de dev créés par l'IaC derrière `enable_test_users` : un admin, deux étudiants (A et B, nécessaires au BOLA).
- Identifiants lus par la CI dans SSM Parameter Store (SecureString) via OIDC. Jamais dans le dépôt, les logs ou les rapports.
- Données créées par les tests : préfixe `qa-<run-id>`, nettoyées en fin de test ; un balayage nocturne supprime les restes `qa-*` périmés.
- Aucune donnée personnelle réelle ; adresses SES de démo uniquement (sandbox, identités vérifiées).
- Jeux de questions du chat (dans le périmètre / hors périmètre) versionnés dans `tests/` avec la réponse attendue.

## 7. Gestion des défauts

1. Toute anomalie devient une issue (labels `type/`, `area/`, `role/`, `priority/`) avec : test en échec, étapes, environnement, version, extrait de log sans donnée sensible.
2. Sévérité : critique (faille de sécurité, perte de données, service indisponible), majeure (AC `must` non tenu), mineure, cosmétique.
3. Une anomalie critique bloque S5 ; une majeure bloque la release sauf dérogation écrite du PO.
4. Le correctif inclut un test de non-régression nommé d'après l'AC concerné.
5. Un test instable est mis en quarantaine avec une issue ouverte, jamais ignoré en silence. Un skip d'outil de sécurité exige la justification inline prévue par les règles du dépôt.

## 8. Cas de sécurité obligatoires

- Sans token : 401. Token invalide ou expiré : 401. Étudiant sur route admin : 403.
- BOLA : l'étudiant A ne lit ni ne modifie le ticket de B (403 ou 404, jamais 200). L'identité vient du `sub` du JWT, jamais du corps de requête.
- Upload > 10 Mo ou type non image : refusé par la politique du POST pré-signé.
- WAF : rafale au-dessus du seuil → 429 ou 403 (via CloudFront et en direct sur `execute-api`) ; charge utile connue comme malveillante bloquée.
- Chat : question hors périmètre → refus ancré + proposition de ticket, sans réponse inventée.
- HTTPS : redirection depuis HTTP, en-têtes HSTS, CSP, nosniff présents.

## 9. Responsabilités

| Domaine | QE | SE |
|---|---|---|
| Stratégie, matrice, critères de sortie | propriétaire | relecture |
| `UNIT-*`, `INT-*` (IaC) | écrit et maintient | n/a |
| `SMK-*`, `SEC-*`, `PERF-*`, `E2E-*`, `DAST-*` | écrit et maintient | fournit contrat, comportements et correctifs |
| `SVC-*` (tests unitaires des fonctions) | revue de la couverture des AC | écrit et maintient |
| `packages/contracts` | consommateur, signale les écarts | propriétaire du contenu |
| Triage des défauts | priorise avec le PO | corrige le code applicatif |
| Infra, CI, utilisateurs de test | demande | OPS fournit |

## 10. Points ouverts

- AC à synchroniser avec les issues (origine : branche distante, non disponible ici).
- Pièce jointe JPG/PNG ≤ 10 Mo : à valider par le PO (US04).
- L'exigence « < 2 s » n'a pas d'identifiant dans le backlog ; `NFR-PERF` est provisoire.
- Aucun ID de module ni de route d'API définitif : à compléter avec `infra/modules/` et `packages/contracts`.
- Le test de bout en bout de l'ingestion (US07) et des e-mails (US09) dépend d'un accès de lecture aux journaux de dev, à définir avec OPS.

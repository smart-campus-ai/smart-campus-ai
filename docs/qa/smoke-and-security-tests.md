# Tests smoke et sécurité post-déploiement (EN-83)

Suites Hurl exécutées sur l'environnement **dev** après chaque déploiement. Elles bloquent la promotion vers prod (S3 puis S5 de [`test-strategy.md`](test-strategy.md)). La matrice de couverture est dans [`traceability.md`](traceability.md).

## Contenu

| Fichier | AC | Tests de la stratégie | Vérifie |
|---|---|---|---|
| `tests/smoke/EN83-AC1-spa-reachable.hurl` | EN83-AC1 | SEC-014 | SPA en 200 sur CloudFront ; HTTP redirigé en 301 vers HTTPS |
| `tests/smoke/EN83-AC1-api-reachable.hurl` | EN83-AC1 | SMK-004, SMK-010 | API joignable via CloudFront et `execute-api` (401 JSON sans token) ; liste étudiant 200 ; KPI admin 200 |
| `tests/smoke/US04-AC1-AC2-create-ticket.hurl` | US04-AC1, US04-AC2 | SMK-001, SMK-002 | création 201 avec statut `Ouvert`, relecture ; titre absent ou vide → 400 |
| `tests/security/EN83-AC1-security-headers.hurl` | EN83-AC1, EN-21-AC2 | SEC-015 | HSTS, CSP `frame-ancestors 'none'`, `nosniff`, Referrer-Policy |
| `tests/security/EN83-AC2-no-token-401.hurl` | EN83-AC2, EN-32-AC1 | SEC-001 | sans token → 401 (lecture, création, KPI ; CloudFront et `execute-api`) |
| `tests/security/EN83-AC2-invalid-token-401.hurl` | EN83-AC2, EN-32-AC2 | SEC-002 | valeur non JWT, JWT mal formé, vrai token à signature altérée → 401 |
| `tests/security/EN83-AC2-student-on-admin-403.hurl` | EN83-AC2, US01-AC5, US05-AC3 | SEC-004, SEC-016 | étudiant sur `/api/kpi` → 403 ; admin → 200 (témoin) |
| `tests/security/EN83-AC2-cors-foreign-origin.hurl` | EN83-AC2 | n/a | aucune en-tête `Access-Control-Allow-*` pour `Origin: https://evil.example` |
| `tests/security/EN83-AC3-US03-AC3-bola.hurl` | EN83-AC3, US03-AC3 | SEC-005, SEC-006 | A ne lit, ne modifie ni ne liste le ticket de B (403/404, aucune donnée de B) ; B garde son ticket intact |
| `tests/security/EN83-AC4-US04-AC5-upload-limits.hurl` | EN83-AC4, US04-AC5, EN-43-AC2 | SMK-020, SEC-007, SEC-008 | POST pré-signé : image valide acceptée ; > 10 Mo, type non image, clé hors préfixe refusés |
| `tests/security/EN83-AC5-waf-known-bad-payload.hurl` | EN83-AC5, RF04-AC3 | SEC-011 | XSS, motif Log4Shell, traversée de chemin → 403 (les deux web ACL) |
| `tests/security/optin/EN83-AC2-expired-token-401.hurl` | EN83-AC2 | SEC-003 | token expiré → 401 (opt-in) |
| `tests/security/optin/EN83-AC5-waf-rate-limit.hurl` | EN83-AC5, RF04-AC2 | SEC-009, SEC-010 | rafale au-delà du seuil → 403 ou 429 (opt-in, dev uniquement) |

Chaque requête porte un commentaire `# <ID d'AC> <comportement>` qui sert de nom de test. Le répertoire `optin/` est exclu des globs par défaut.

## Variables

Aucune valeur n'est codée en dur. Modèle : `tests/smoke/vars.dev.properties.example` (non secret, à copier en `vars.dev.properties`, ignoré par git via `tests/.gitignore`).

| Variable | Fournie par | Secret | Usage |
|---|---|---|---|
| `spa_url` | fichier `.properties` | non | URL CloudFront, sans `/` final |
| `spa_host` | fichier `.properties` | non | même hôte sans schéma (redirection HTTP) |
| `api_url` | fichier `.properties` | non | URL `execute-api` avec le stage, sans `/` final |
| `ticket_category` | fichier `.properties` | non | catégorie valide du schéma de ticket |
| `student_a_token`, `student_b_token`, `admin_token` | CI | **oui** | JWT Cognito des utilisateurs de test |
| `expired_token` | CI | **oui** | uniquement pour le test opt-in du token expiré |

Les jetons viennent des utilisateurs de test créés par l'IaC (`enable_test_users`). La CI les lit dans SSM Parameter Store (SecureString) via OIDC, obtient les JWT auprès de Cognito, puis les injecte. Ils ne sont jamais écrits dans un fichier ni dans les logs.

Deux modes d'injection :

- `--secret nom=valeur` : valeur masquée dans les logs Hurl (à privilégier pour les appels directs) ;
- variables d'environnement `HURL_VARIABLE_nom=valeur` : nécessaire avec `task smoke`, qui ne transmet pas d'options supplémentaires. À exporter depuis une étape où le masquage est actif (`::add-mask::` dans GitHub Actions).

## Exécution en local

Prérequis : toolchain installée (`task setup`), credentials AWS obtenus par SSO pour lire SSM (jamais lus par les agents), `hurl` épinglé dans `.mise.toml`.

```sh
# 1. Variables non secrètes
cp tests/smoke/vars.dev.properties.example tests/smoke/vars.dev.properties
# renseigner spa_url, spa_host, api_url, ticket_category

# 2. Jetons (obtenus par vos soins, par exemple depuis SSM puis Cognito), exportés dans le shell uniquement
export HURL_VARIABLE_student_a_token="..."
export HURL_VARIABLE_student_b_token="..."
export HURL_VARIABLE_admin_token="..."

# 3. Smoke
task smoke ENV=dev
```

Sécurité (pas encore de cible Taskfile) :

```sh
# Fichiers factices pour l'upload, générés hors dépôt
qa_dir="$(mktemp -d)"
head -c 1024 /dev/zero > "$qa_dir/qa-small.bin"
head -c 10485761 /dev/zero > "$qa_dir/qa-oversize.bin"

hurl --test \
  --variables-file tests/smoke/vars.dev.properties \
  --file-root "$qa_dir" \
  --glob "tests/security/*.hurl"

rm -rf "$qa_dir"
```

Tests opt-in (dev uniquement, en dernier) :

```sh
hurl --test --variables-file tests/smoke/vars.dev.properties \
  tests/security/optin/EN83-AC5-waf-rate-limit.hurl
```

Le test de débit WAF dure environ 2 minutes par URL et laisse l'IP de l'exécuteur bloquée quelques minutes : ne rien lancer d'autre depuis cette IP juste après.

## Exécution en CI

- Déclenchement : après l'apply de `develop` vers dev, jamais sur une PR de code. La promotion `develop` → `main` exige `smoke` et `security` verts sur la dernière version dev (AC6).
- Rapport : ajouter `--report-junit reports/hurl-<suite>.xml` et publier l'artefact.
- Le workflow est écrit par OPS (`.github/`). Étapes attendues : OIDC, lecture des identifiants des utilisateurs de test, obtention des JWT, `task smoke ENV=dev`, génération des fichiers factices, commande Hurl de sécurité, opt-in WAF en dernier (job nocturne ou manuel).
- Prod : seules les suites dev servent de gate ; aucun utilisateur de test ni test de débit WAF en prod, donc `task smoke ENV=prod` n'est pas prévu.

## Hypothèses à confirmer

Les routes et schémas ne sont pas encore dans `packages/contracts` (absent du dépôt). À aligner avec SE :

- routes : `GET/POST /api/tickets`, `GET/PATCH /api/tickets/{id}`, `GET /api/kpi` (admin), `POST /api/tickets/{id}/attachments` ;
- corps de ticket `{title, description, category}`, réponse avec `id`, `title`, `status`, `description` ;
- réponse d'attachement `{url, fields{key, policy, x-amz-algorithm, x-amz-credential, x-amz-date, x-amz-signature, x-amz-security-token}}`, le champ `Content-Type` étant choisi par le client ;
- les JWT fournis sont acceptés par l'authorizer REST sans scope (ID token).

Points d'attention :

- Si CloudFront transforme les 403/404 de l'API en page SPA (réponses d'erreur personnalisées), les assertions 403 via CloudFront échouent volontairement : c'est un défaut d'infra à corriger.
- L'API n'a pas de route de suppression : les tickets `qa-*` sont purgés par le balayage nocturne ; l'objet de 1 Kio téléversé expire par cycle de vie.
- SEC-019 (propriétaire ignoré dans le corps), SEC-012, SEC-013 (chat) et SEC-017 ne sont pas couverts par ce lot.

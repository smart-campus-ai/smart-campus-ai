# Variables et secrets GitHub attendus par la CI

Les workflows AWS n'utilisent **aucune clé longue durée** : ils assument un rôle IAM par OIDC (ADR-0012). Les ARN et noms ci-dessous ne sont pas confidentiels, ce sont donc des **variables** GitHub (Settings → Secrets and variables → Actions → Variables), jamais des secrets. Toutes les valeurs viennent des sorties de `infra/bootstrap` (apply local par un humain, ADR-0009).

Tant que `AWS_PLAN_ROLE_ARN` est vide, `iac-plan` se termine en succès avec une annotation « Plan skipped » : rien à configurer pour que le dépôt reste vert avant le bootstrap.

## Variables au niveau du dépôt

Lues par les jobs `pull_request`, qui s'exécutent hors de tout environnement GitHub.

| Variable | Valeur | Sortie du bootstrap | Utilisée par |
|---|---|---|---|
| `AWS_PLAN_ROLE_ARN` | ARN du rôle `sc-gha-plan` (lecture seule, confiance `pull_request`) | `github_plan_role_arn` | `iac-plan` |
| `STATE_KMS_KEY_ARN` | ARN complet de la clé KMS du state | `state_kms_key_arn` | `iac-plan` (`kms_key_id` du backend surchargé par `task plan`, et `TF_VAR_state_kms_key_arn` pour le bloc `encryption` du state et du plan) |
| `STATE_BUCKET` | Nom du bucket de state | `state_bucket_name` | `iac-plan` (`task plan` surcharge `bucket` de `infra/envs/<env>/backend.hcl` via `-backend-config`) ; repris par les workflows d'apply (EN-73) |
| `AWS_REGION` | Région principale : `us-east-1` pour le workshop (le compte n'autorise les services de la plateforme que dans cette région) ; `eu-west-3` reste un paramètre pour une vraie production. Optionnelle, `us-east-1` par défaut | `aws_region` | `iac-plan` |
| `AWS_ACCOUNT_ID` | ID du compte AWS (12 chiffres, non secret : variable, pas secret) | aucune (`aws sts get-caller-identity` ou console) | aucun workflow pour l'instant ; réservé à la construction d'ARN |

## Variables par environnement GitHub (`dev`, `prod`)

Créer les environnements `dev` et `prod` (Settings → Environments). `prod` exige des relecteurs et limite les branches de déploiement à `main` : c'est la vraie protection de ce rôle (ADR-0012, risque 1).

| Variable | Valeur | Sortie du bootstrap | Utilisée par |
|---|---|---|---|
| `AWS_APPLY_ROLE_ARN` | ARN du rôle `sc-gha-apply-<env>` de l'environnement | `github_apply_role_arns["<env>"]` | `iac-apply` (EN-73) |
| `STATE_BUCKET`, `STATE_KMS_KEY_ARN`, `AWS_REGION` | mêmes valeurs qu'au niveau du dépôt, à redéfinir ici si l'environnement doit les surcharger | voir ci-dessus | `iac-apply` (EN-73) |

Le rôle plan n'a **pas** de variable par environnement : un plan de PR ne couvre que `dev`. Le plan de `prod` se calcule dans le job d'apply de `prod`, après approbation.

## Secret optionnel

| Secret | Rôle | Sans le secret |
|---|---|---|
| `INFRACOST_API_KEY` | Clé d'API Infracost (compte gratuit), pour ajouter l'écart de coût mensuel au commentaire de plan | L'étape est ignorée avec une annotation « Infracost skipped » ; le plan est commenté sans estimation de coût |

Définir ce secret au niveau du dépôt (Settings → Secrets and variables → Actions → Secrets). Il n'est jamais affiché dans les journaux. Les PR de forks n'y ont pas accès.

## Renseigner les variables après le bootstrap

À faire par l'OPS, une fois `infra/bootstrap` appliqué et les sorties relevées (`tofu -chdir=infra/bootstrap output`) :

1. Variables du dépôt : `AWS_PLAN_ROLE_ARN`, `STATE_KMS_KEY_ARN`, `STATE_BUCKET`, `AWS_REGION` (`us-east-1`), `AWS_ACCOUNT_ID`.
2. Variable `AWS_APPLY_ROLE_ARN` dans chacun des environnements `dev` et `prod`.
3. Pour un plan local, renseigner `bucket` et `kms_key_id` dans `infra/envs/<env>/backend.hcl` (valeurs non secrètes, via une PR) ou exporter `STATE_BUCKET`, `STATE_KMS_KEY_ARN` et `TF_VAR_state_kms_key_arn` avant `task plan ENV=dev STACK=platform`. La CI n'en a pas besoin : elle surcharge les placeholders depuis les variables GitHub. La clé de state est `<env>/<stack>.tfstate` (ADR-0011).
4. Ouvrir une PR qui modifie `infra/` : les jobs `plan (foundation)` et `plan (platform)` publient un commentaire par stack.

## Contrôles et limites

- Une PR depuis un fork ne reçoit ni jeton OIDC ni secret : le plan est ignoré avec une annotation.
- Si `AWS_PLAN_ROLE_ARN` est défini mais pas `STATE_KMS_KEY_ARN` ou `STATE_BUCKET`, le job échoue : le plan ne pourrait pas lire ni déchiffrer le state.
- `Taskfile.yml` est un fichier de garde restauré depuis la base de la PR (ADR-0010) : la cible `plan` corrigée ne s'applique en CI qu'après le merge de la PR qui la modifie.
- Le job de plan de la PR qui introduit `iac-plan` échoue tant qu'elle n'est pas fusionnée : le `Taskfile.yml` de la base n'a pas encore la cible `plan:preflight` (ADR-0010). Ce comportement est attendu, il disparaît après le merge.
- Le fichier de plan reste dans le répertoire temporaire du runner, chiffré par OpenTofu, et n'est jamais publié en artefact.
- Un commentaire unique par stack (`dev / foundation`, `dev / platform`) est créé puis mis à jour à chaque push de la PR.

## Durcissement du plan de PR (HCL non fiable)

Le HCL d'une PR s'exécute pendant le plan avec les identifiants du rôle plan. `iac-plan` applique donc :

- **Aucun texte de plan dans le journal ni dans le commentaire.** Le plan est écrit dans un fichier ; en cas d'échec, seuls le code de sortie et au plus 5 lignes `Error:` d'OpenTofu sont journalisés. Le commentaire contient les comptes (`Plan: x to add…`) et, par ressource, l'action et l'adresse issues de `tofu show -json` : jamais de valeur d'attribut. Les clés d'instance (`["..."]`, `[0]`) sont remplacées par `[*]` puis les lignes identiques sont agrégées (`<n>x <action> <adresse>`), donc aucune clé de `for_each` n'atteint le commentaire. En cas d'échec, le commentaire indique seulement « Plan failed ».
- **Providers vérifiés avant les identifiants.** L'étape « Pre-flight » (`task plan:preflight`, `scripts/ci/check-tofu-providers.sh`) télécharge les providers avec `tofu init -backend=false` dans un cache fixe (`$RUNNER_TEMP/tf-plugin-cache`), puis échoue si `tofu providers` ou le fichier de verrouillage listent un provider hors de `hashicorp/aws`, `hashicorp/random`, `hashicorp/archive`, si un module n'est pas local, ou si `infra/` contient (dans `*.tf`, `*.tofu`) `data "external"`, `data "http"`, un bloc `provisioner`, un `key_provider "external"` ou `method "external"` (bloc `encryption`), ou un fichier `*.tf.json` / `*.tofu.json`. L'étape vide aussi `ACTIONS_ID_TOKEN_REQUEST_TOKEN` et `_URL` : le `tofu init` du pré-contrôle charge le HCL de la PR alors que le job a `id-token: write`. L'`init` avec identifiants utilise ensuite `-plugin-dir` sur ce cache : rien n'est téléchargé après l'assume-role. Pour autoriser un nouveau provider, modifier `ALLOWED_PROVIDERS` dans le script (fichier de garde, ADR-0010) via une PR relue par l'OPS.
- **Pas de jeton OIDC pour le HCL.** `ACTIONS_ID_TOKEN_REQUEST_TOKEN` et `ACTIONS_ID_TOKEN_REQUEST_URL` sont vidés dans chaque étape après l'assume-role (`env:` puis `unset` dans le script).
- **Infracost isolé.** Étape séparée, sans variables `AWS_*` (`env -u`), avec `INFRACOST_API_KEY` uniquement sur cette étape : `tofu show` et ses providers ne voient jamais la clé.
- **Commentaire assaini.** Fence Markdown dynamique (plus longue que toute suite de `~` du contenu) et `@` neutralisés pour éviter les mentions.

Ces garde-fous s'ajoutent au rôle plan à permissions minimales (ADR-0012 : pas de `secretsmanager:GetSecretValue`, pas de lecture des `SecureString`, `kms:Decrypt` limité à la clé du state, pas de lecture des données S3 et DynamoDB hors state). `scripts/ci/` est restauré depuis la base de la PR : le script corrigé ne s'applique en CI qu'après le merge de la PR qui le modifie.

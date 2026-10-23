# Déploiement applicatif et rollback

Pipeline : `.github/workflows/app-deploy.yml` (EN-74). L'infra possède la configuration des fonctions, ce pipeline possède leur code (OpenTofu ignore le code). Contrat avec SE : `CONTRIBUTING.md`, section « Contrat infra ↔ app ».

## Flux

| Déclencheur | Environnement | Approbation |
|---|---|---|
| push `develop` touchant `services/**` ou `frontend/**` | `dev` | non |
| push `main` touchant `services/**` ou `frontend/**` | `prod` | oui (environnement GitHub `prod`) |
| `workflow_dispatch` sur `develop` ou `main` | idem selon la branche | idem |

Sans entrées de rollback, un `workflow_dispatch` redéploie tout (sans effet sur les fonctions dont le code n'a pas changé). Sur une autre branche, le workflow échoue.

0. `auth` (environnement GitHub, sans checkout ni droit de jeton) : choisit le mode d'authentification AWS une seule fois (section « Authentification AWS ») ; les jobs AWS suivent sa sortie.
1. `prepare` : déduit l'environnement de la branche, liste les services (`services/<fonction>/` avec `package.json`, `requirements.txt` ou `pyproject.toml`) et détecte `frontend/package.json`. **Une exécution qui ne déploierait rien échoue** (jamais un succès vert sans effet) :
   - aucun service déployable et pas de `frontend/package.json` : erreur `Nothing to deploy` ;
   - un push qui modifie `services/<nom>/` alors que ce dossier existe sans manifeste : erreur `Service not deployable` (la plage `avant..après` du push est comparée, d'où `fetch-depth: 0` ; plage inconnue, branche neuve ou push forcé : seule la première règle s'applique).
   Une fonction dont le code est identique à celui servi par `live` reste ignorée sans erreur (relance, changement limité à des tests ou à de la documentation) : c'est une idempotence voulue, signalée par une annotation `Nothing to deploy` du job `deploy-lambda`.
2. `build-lambda` (une exécution par service, sans accès AWS) : action `.github/actions/lambda-package`, zip **arm64** reproductible, somme SHA-256, artefact GitHub.
   - Node : installation figée (`pnpm-lock.yaml` ou `package-lock.json`), scripts de cycle de vie désactivés. Avec un script `build`, il doit produire un bundle autonome dans `dist/` (racine du zip) ; sans script `build`, sources et `node_modules` de production.
   - Python : `requirements.txt` ; wheels binaires `manylinux` aarch64 uniquement, version cible via l'entrée `python-version` (3.12 par défaut). Le fichier doit être **entièrement figé et haché** : chaque ligne `nom==version` avec au moins un `--hash=sha256:<64 hex>`, dépendances transitives comprises (`pip-compile --generate-hashes` ou `uv export`), sans ligne d'option (`-r`, `-e`, `--index-url`). L'installation utilise `pip --require-hashes` ; un fichier non conforme fait échouer la construction avant tout téléchargement.
   - Refus si un fichier ressemblant à un secret est présent dans le service (`.env`, `*.pem`, `*.key`, `*.tfstate`…) ou si un binaire natif n'est pas aarch64.
3. `build-spa` (sans accès AWS) : `pnpm install --frozen-lockfile` puis `pnpm run build` dans `frontend/` ; le résultat est attendu dans `frontend/dist/` avec un `index.html`.
4. `deploy-lambda` (environnement GitHub) pour chaque fonction `sc-<env>-<service>` :
   - compare le `CodeSha256` de la version servie par `live` à celui du zip : identique ⇒ fonction ignorée ;
   - dépose le zip dans `s3://$ARTIFACTS_BUCKET/<env>/lambda/<service>/<sha git>.zip` avec les métadonnées `sha256` et `git-sha` et la somme de contrôle S3 SHA-256 ;
   - `update-function-code` depuis S3, attente, `publish-version --code-sha256` (refuse de publier si `$LATEST` n'est pas exactement l'artefact), attente de l'état `Active` ;
   - **smoke tests de pré-bascule (EN-74 AC2)** : chaque nouvelle version publiée (immuable, sans trafic) est invoquée directement (`lambda invoke --qualifier <version>`) avec l'événement `services/<service>/smoke-event.json`. Le test échoue si ce fichier manque ou n'est pas un objet JSON, si l'invocation échoue, si la fonction renvoie une erreur (`FunctionError`) ou une réponse avec `statusCode` ≥ 500. Le corps de la réponse n'est jamais journalisé. **Aucun alias ne bouge tant qu'une version échoue** ;
   - bascule de l'alias `live` (complète, ou canari si `CANARY_WEIGHT` est défini) ;
   - `task smoke ENV=<env>` (Hurl, `tests/smoke/`) ;
   - **en cas d'échec après la bascule, `live` revient automatiquement à la version précédente pour toutes les fonctions changées par l'exécution.** Le récapitulatif de l'exécution liste fonction, version précédente et nouvelle version.
5. `publish-spa` (environnement GitHub), en parallèle des Lambdas :
   - vérification du propriétaire des buckets (`list-objects-v2 --expected-bucket-owner`, voir les droits ci-dessous), lecture du pointeur `current` (build servi avant l'exécution, exposé en sortie `restore_sha`), puis copie du build dans `s3://$ARTIFACTS_BUCKET/<env>/spa/<sha git>/` (sert au rollback), avec un fichier `SHA256SUMS` déposé en dernier (hors de l'arbre publié) ;
   - synchronisation vers `$SPA_BUCKET` : `assets/*` en `public, max-age=31536000, immutable`, le reste en `no-cache`, `index.html` en dernier (`no-cache`) ;
   - invalidation CloudFront de `/index.html` uniquement ;
   - suppression des fichiers obsolètes (`--delete`) après l'invalidation ;
   - pointeurs `s3://$ARTIFACTS_BUCKET/<env>/spa/current` et `previous` mis à jour.
6. `revert-spa` (environnement GitHub), **uniquement si `deploy-lambda` ou `publish-spa` a échoué ou été annulé** : attend la fin des deux jobs, récupère le build `restore_sha` dans la copie de rollback, le contrôle avec `SHA256SUMS`, le republie (mêmes en-têtes de cache), invalide `/index.html`, supprime les fichiers obsolètes, puis remet `current` sur ce build (et `previous` sur le build en échec s'il avait été enregistré, pour pouvoir revenir en avant). Première livraison sans SPA précédente : avertissement, rien à restaurer. En prod, ce job est lié à l'environnement et demande donc la même approbation que le déploiement.

Un seul déploiement à la fois par environnement (`concurrency`, jamais annulé en cours). Une exécution en attente peut être remplacée par une plus récente : sans risque, car la comparaison se fait sur le contenu déployé et non sur le diff du push.

## Authentification AWS (ADR-0016, atelier)

Décision OPS : pas d'OIDC GitHub pendant l'atelier. La CI s'authentifie avec les identifiants de **session** de l'atelier, stockés comme secrets de l'environnement GitHub `dev`. Le job `auth` applique cet ordre, une fois par exécution :

| Priorité | Condition | Mode | Jobs AWS |
|---|---|---|---|
| 1 | `AWS_DEPLOY_ROLE_ARN` (`sc-<env>-app-deploy`) ou, à défaut, `AWS_APPLY_ROLE_ARN` (`sc-gha-apply-<env>`) non vide | OIDC (`role-to-assume`), action `aws-oidc` | exécutés |
| 2 | les trois secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` présents, **environnement `dev` et branche `develop` uniquement** | identifiants de session, via les entrées de `aws-actions/configure-aws-credentials` (même SHA épinglé que `aws-oidc`) | exécutés |
| 3 | rien de configuré | aucun | push sur `dev` : jobs AWS **ignorés** avec une annotation `Deployment skipped` ; exécution manuelle ou `prod` : **échec** |

Un jeu de secrets incomplet (un ou deux sur trois) échoue. Les secrets sont refusés pour `prod` : `prod` n'est pas déployé pendant l'atelier et exige un rôle OIDC.

Garde-fous :

- Les jobs AWS portent `environment: dev`, déployable depuis `develop` uniquement (règle de branches de déploiement de l'environnement) : aucun job de PR n'accède aux secrets. Le workflow n'a pas de déclencheur `pull_request` (donc jamais sur une PR de fork), et `auth` refuse tout événement autre que `push` et `workflow_dispatch`.
- Les plans de PR : les secrets de `dev` n'existent pas pour les références de PR ; en mode secrets, le job de plan de `iac-plan.yml` est donc ignoré avec une annotation, et le plan s'exécute dans le job d'apply sur `develop` (plan figé). Ce comportement est à porter par `iac-plan.yml` (hors périmètre de `app-deploy.yml` et de ce runbook).
- Aucun secret n'est affiché ni placé dans un `env:` : sa valeur n'apparaît que comme entrée de `configure-aws-credentials` (qui la masque). Le job `auth` ne lit que des booléens (`secrets.X != ''`). Les variables `AWS_*` exportées par l'action restent nécessaires aux étapes `aws` ; elles sont vidées pour les étapes qui exécutent du code du dépôt (smoke tests).
- Limite à connaître : en mode secrets, les droits sont ceux du rôle de la session de l'atelier, **plus larges** que la politique `sc-<env>-app-deploy` du tableau ci-dessous, et la région est `us-east-1`. Ce compromis est accepté par l'ADR-0016 pour l'atelier.

### Renouvellement des identifiants (OPS)

Les identifiants de session expirent. Un push sur `develop` après expiration échoue à l'étape d'authentification (jetons expirés). L'OPS renouvelle les trois secrets :

1. Récupérer les identifiants temporaires depuis Workshop Studio (accès en ligne de commande / variables d'environnement), sans les copier dans un fichier du dépôt, un ticket ou un message.
2. Settings → Environments → `dev` → Secrets : remplacer `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` et `AWS_SESSION_TOKEN` (les trois ensemble, sinon l'exécution échoue pour « Incomplete credentials »).
3. Vérifier la variable `AWS_REGION` = `us-east-1` sur l'environnement `dev`.
4. Relancer l'exécution échouée (*Re-run all jobs*) ou lancer *Run workflow* sur `develop`.

## Variables attendues par environnement

À définir dans Settings → Environments → `dev` / `prod` → Variables (jamais en secret ni en clair dans un workflow), hors les trois secrets de la section précédente.

| Variable | Obligatoire | Rôle |
|---|---|---|
| `AWS_DEPLOY_ROLE_ARN` | non (mode OIDC) | rôle dédié `sc-<env>-app-deploy` assumé par OIDC (ADR-0012, `sub` = `environment:<env>`). Le job `auth` refuse tout autre nom. Prioritaire sur `AWS_APPLY_ROLE_ARN` et sur les secrets |
| `AWS_APPLY_ROLE_ARN` | non (mode OIDC, repli) | rôle apply de l'IaC `sc-gha-apply-<env>`, utilisé seulement si `AWS_DEPLOY_ROLE_ARN` est vide ; élargit les droits d'un déploiement applicatif à ceux de l'apply, à éviter hors atelier |
| `ARTIFACTS_BUCKET` | oui | bucket des artefacts (zip Lambda, builds SPA) |
| `SPA_BUCKET` | oui | bucket privé de la SPA |
| `CLOUDFRONT_DISTRIBUTION_ID` | oui | distribution à invalider |
| `AWS_REGION` | non | défaut `us-east-1` (ADR-0013), y compris dans l'action `aws-oidc` |
| `CANARY_WEIGHT` | non | part de trafic envoyée à la nouvelle version, de `0.01` à `0.99` ; vide = bascule complète |
| `CANARY_BAKE_SECONDS` | non | attente avant les smoke tests en mode canari, défaut `60` |

Prérequis hors pipeline :

- Les fonctions `sc-<env>-<service>` (architecture `arm64`) et leur alias `live` existent déjà, créés par l'infra. Le pipeline échoue avec un message explicite sinon.
- **Pas de dérive OpenTofu (EN-74 AC5).** Le pipeline change le code de `$LATEST`, publie des versions et déplace l'alias `live`, sans toucher à la configuration (`update-function-configuration` n'est jamais appelé). Le module `infra/modules/lambda-service` porte `lifecycle { ignore_changes }` sur `filename`, `source_code_hash`, `s3_key` et `s3_object_version` (ressource fonction) et sur `function_version` (alias `live`). Vérification après un déploiement en dev : `task plan ENV=dev STACK=platform` ne doit montrer aucune différence sur les fonctions.
- Contrat avec SE : chaque `services/<service>/` fournit `smoke-event.json`, un objet JSON que le handler traite sans effet de bord (pas d'écriture, pas d'envoi) ; il sert aux smoke tests de pré-bascule. Les dépendances Python sont figées avec leurs hachages (section Flux, étape 2).
- L'environnement GitHub `prod` exige une approbation et limite les branches de déploiement à `main` (ADR-0012, risque 1) : `sub` ne prouve pas la branche.
- **Droits exacts du rôle `sc-<env>-app-deploy` (EN-74 AC6, mode OIDC).** Rien d'autre que ce tableau (le test `workflow.test.sh` compare les appels AWS du workflow à cette liste) :

  | Action | Ressource | Appelée par |
  |---|---|---|
  | `lambda:GetAlias`, `lambda:GetFunctionConfiguration` | `function:sc-<env>-*` | état et architecture avant publication ; rollback |
  | `lambda:GetFunction` | `function:sc-<env>-*` | attentes `function-updated-v2` / `function-active-v2` |
  | `lambda:UpdateFunctionCode`, `lambda:PublishVersion` | `function:sc-<env>-*` | mise à jour du code et publication |
  | `lambda:UpdateAlias` | `function:sc-<env>-*:live` | bascule, retour arrière, rollback |
  | `lambda:InvokeFunction` | `function:sc-<env>-*:*` (versions numérotées uniquement, jamais `$LATEST` ni l'alias) | smoke tests de pré-bascule |
  | `s3:ListBucket` | bucket d'artefacts, avec la condition `StringLike` `s3:prefix` = `<env>/*` ; bucket SPA, sans condition de préfixe | `s3api list-objects-v2 --prefix <env>/` (artefacts) et `list-objects-v2` (SPA) pour le contrôle du propriétaire ; `aws s3 sync` ; lecture d'un objet absent en 404 plutôt qu'en 403 |
  | `s3:AbortMultipartUpload` | bucket SPA et `artifacts/<env>/*` | envois multipart des commandes `aws s3` au-delà de 8 Mo |
  | `s3:GetObject`, `s3:PutObject` | `artifacts/<env>/*` | zip, copies de rollback, pointeurs ; lecture par Lambda lors de `UpdateFunctionCode` avec les droits de l'appelant |
  | `s3:PutObject`, `s3:DeleteObject` | bucket SPA | publication et suppression des fichiers obsolètes |
  | `kms:GenerateDataKey`, `kms:Decrypt` | clés CMK `data` des deux buckets, avec `kms:ViaService` = `s3.<région>.amazonaws.com` | chiffrement SSE-KMS |
  | `cloudfront:CreateInvalidation` | la distribution | invalidation `/index.html` |

  **Pourquoi pas `head-bucket`.** `HeadBucket` exige `s3:ListBucket` sans préfixe : la requête n'envoie pas de paramètre `prefix`, donc la condition `s3:prefix` du bucket d'artefacts ne correspond pas et l'appel est refusé. Le pipeline contrôle le propriétaire avec `s3api list-objects-v2 --bucket <bucket> --prefix "<env>/" --expected-bucket-owner <compte>` (une page, un objet, sortie jetée), qui reste dans le préfixe autorisé. Les autres appels `s3api` du workflow sont `put-object` (`s3:PutObject`) ; aucun `head-bucket` ni `head-object` n'est utilisé.

  `sts:GetCallerIdentity` n'exige aucune permission. Aucune action IAM, aucun `Action: *`, aucune `Resource: *` (les API sans ressource sont absentes de la liste). Le rôle porte la permissions boundary du projet, une politique de confiance `sub` = `repo:<org>/<repo>:environment:<env>` avec `aud` = `sts.amazonaws.com`, et ses actions sont limitées à la région `AWS_REGION` (`aws:RequestedRegion`).
- Toutes les instructions S3 du rôle portent la condition `StringEquals: { "s3:ResourceAccount": "${aws:PrincipalAccount}" }` : un nom de bucket mal saisi (les noms sont devinables dans un dépôt public) ne peut pas pointer vers le bucket d'un autre compte. Le pipeline double cette protection : après l'assomption du rôle, il vérifie le propriétaire de chaque bucket (`s3api list-objects-v2 --expected-bucket-owner`) avant toute écriture, et les appels `s3api` portent `--expected-bucket-owner` (les commandes `aws s3` de haut niveau n'ont pas cette option).
- **Suivi à ouvrir (`role/ops`) : ajouter le rôle `sc-<env>-app-deploy` au module `github-oidc`.** Le job `auth` lit `AWS_DEPLOY_ROLE_ARN` et vérifie que le nom du rôle est `sc-<env>-app-deploy` (repli : `AWS_APPLY_ROLE_ARN`, rôle `sc-gha-apply-<env>`). Tant que le rôle n'existe pas et que la variable n'est pas définie, `dev` fonctionne avec les secrets de session (section précédente) et un push sur `main` (`prod`) touchant `services/**` ou `frontend/**` **échoue** (volontairement : pas de faux succès). Le pipeline retire en outre les identifiants AWS et les variables de demande de jeton OIDC des étapes qui exécutent du code du dépôt (smoke tests, outils mise).

## Rollback

### Automatique

Les smoke tests de pré-bascule en échec n'atteignent jamais l'alias : rien à restaurer côté Lambda. Échec des smoke tests après la bascule, annulation ou dépassement du délai du job (ou échec de toute étape suivante du job `deploy-lambda`) : l'étape « Revert the aliases » repointe `live` sur la version précédente et efface le routage canari. Vérifier dans le récapitulatif de l'exécution et dans les annotations. Si l'étape signale `Revert failed`, passer au rollback manuel ci-dessous sans attendre.

**La SPA revient avec les alias** : si `deploy-lambda` (ou `publish-spa`) échoue ou est annulé, le job `revert-spa` republie dans la même exécution le build qui était servi avant elle et invalide CloudFront (voir Flux, étape 6). Un job `revert-spa` en échec (copie de rollback absente ou altérée, `SHA256SUMS` invalide) laisse la SPA en l'état : passer au rollback SPA manuel. Si seule la publication de la SPA échoue, les Lambdas restent sur les nouvelles versions et la SPA revient à l'ancien build : les deux versions de l'API doivent rester compatibles avec la SPA précédente.

### Manuel : Lambda

1. Identifier la version à restaurer : récapitulatif de l'exécution fautive (colonne « Previous »), ou, depuis un poste autorisé :
   `aws lambda list-versions-by-function --function-name sc-<env>-<service> --query 'Versions[].[Version,Description,LastModified]' --output table`
   (la description contient le SHA git du déploiement).
2. Actions → **app-deploy** → *Run workflow* sur la branche de l'environnement (`develop` pour dev, `main` pour prod) avec :
   - `rollback_function` : nom du dossier, par exemple `tickets` ;
   - `rollback_version` : numéro de version, par exemple `12`.
3. Le job `rollback-lambda` (approbation requise en prod) vérifie que la version est `Active`, repointe `live`, lance les smoke tests et note l'ancienne version dans le récapitulatif (pour revenir en avant, relancer avec ce numéro).

Les versions Lambda publiées sont immuables : revenir en arrière ne dépend pas de l'artefact S3.

### Manuel : SPA

*Run workflow* avec `rollback_spa` :

- `previous` : republie le build qui précédait l'actuel (pointeur `previous`) ;
- ou un SHA git complet (40 caractères) déjà déployé, dont le build est conservé sous `<env>/spa/<sha>/`.

Avant de republier, le job contrôle le build récupéré avec `SHA256SUMS` (`sha256sum --check`, et aucun fichier en trop ou manquant) : une copie incomplète ou modifiée fait échouer le rollback sans rien publier. Un build déployé avant l'introduction de ce fichier n'en a pas et ne peut plus servir de cible ; le rollback échoue alors explicitement. `SHA256SUMS` protège d'une corruption ou d'une modification partielle, pas d'un acteur pouvant écrire à la fois les fichiers et la somme : la protection de fond reste la politique du bucket d'artefacts.

Les deux entrées Lambda et SPA peuvent être fournies ensemble. Le rollback republie les fichiers avec les mêmes en-têtes de cache, invalide `/index.html`, puis échange les pointeurs `current` et `previous`.

### Si le pipeline est indisponible

Dernier recours, par un humain habilité (sans clé longue durée) : `aws lambda update-alias --function-name sc-<env>-<service> --name live --function-version <version> --routing-config '{"AdditionalVersionWeights":{}}'`, puis ouvrir une issue `area/infra` pour tracer l'écart. Les changements de console ou de CLI restent l'exception (AGENTS.md, règle 1).

## Limites connues

- Les rôles et ressources de l'infra (module `lambda-service`, buckets, distribution) sont supposés nommés `sc-<env>-*` ; adapter la variable `fn` du workflow si le module choisit un autre schéma.
- `/index.html` est la seule invalidation : l'entrée `/` du cache CloudFront (objet racine par défaut) et les réponses d'erreur mises en cache pour les routes de la SPA expirent selon leur TTL. À vérifier au premier déploiement en dev.
- Le bundle SPA est construit sans variable d'environnement : la configuration par environnement (identifiants Cognito, URL) doit être lue à l'exécution, pas à la compilation.
- Un déploiement mêle plusieurs fonctions : le retour automatique les restaure toutes, puis `revert-spa` restaure la SPA. Pendant la fenêtre entre la bascule et le retour arrière, SPA et API peuvent différer : un changement de contrat incompatible entre les deux doit être livré en deux temps.
- Les smoke tests de pré-bascule invoquent chaque fonction avec son `smoke-event.json` ; ils ne remplacent pas les tests Hurl post-bascule (`tests/smoke/`, EN-83) qui passent par CloudFront et l'API.
- La région des workflows `iac-plan.yml` et `iac-apply.yml` n'est pas couverte par ce runbook : leur valeur par défaut de `AWS_REGION` est à aligner sur ADR-0013 dans leur propre issue.

## Tests

Deux scripts shell, sans AWS ni réseau, à lancer sur Linux (`bash`, `zip`, `unzip`, `file`, `openssl`, outils GNU) :

- `bash .github/actions/lambda-package/tests/package.test.sh` : exécute `package.sh` dans des espaces de travail jetables avec un `python` factice (arm64, zip reproductible, somme de contrôle, hachages obligatoires, binaires non arm64 refusés) ;
- `bash .github/actions/lambda-package/tests/workflow.test.sh` : assertions statiques sur `app-deploy.yml` et sur ce runbook.

| Critère | Tests automatiques | Vérification en environnement |
|---|---|---|
| EN-74-AC1 artefact arm64, nouvelle version | `package.test.sh` : zip + `.sha256`, `CodeSha256`, reproductibilité, wheels aarch64, binaire x86-64 refusé ; `workflow.test.sh` : action `lambda-package`, refus d'une fonction non arm64, `publish-version --code-sha256` | une fonction `sc-dev-<service>` change de version |
| EN-74-AC2 bascule après smoke tests | `workflow.test.sh` : la porte invoque la version publiée, peut échouer, précède la bascule | alias `live` inchangé si `smoke-event.json` échoue |
| EN-74-AC3 SPA et invalidation | `workflow.test.sh` : `s3 sync` vers `SPA_BUCKET` et `create-invalidation` | invalidation visible dans CloudFront |
| EN-74-AC4 rollback | `workflow.test.sh` : retour des alias, job `revert-spa` (attend les deux déploiements, vérifie, republie, invalide), cible lue avant publication, rollbacks manuels | un échec provoqué en dev restaure alias et SPA |
| EN-74-AC5 pas de dérive | `workflow.test.sh` : seul `update-function-code` est appelé ; `ignore_changes` du module `lambda-service` (ignoré si le module est absent du dépôt) | `task plan ENV=dev STACK=platform` sans différence |
| EN-74-AC6 droits minimaux | `workflow.test.sh` : ARN de rôle validé par `auth` et nom imposé, appels AWS du workflow (`lambda`, `cloudfront`, `s3api`) = actions du tableau ci-dessus, aucun `head-bucket`, contrôle du propriétaire sous le préfixe `<env>/` | lecture de la politique du rôle une fois créé |
| ADR-0013 région | `workflow.test.sh` : `us-east-1` est la seule valeur par défaut (workflow, action `aws-oidc`, runbook) | |
| Configuration manquante | `workflow.test.sh` : les jobs échouent si un bucket ou la distribution manque ; `auth` échoue sans authentification (sauf push sur `dev`, ignoré avec annotation) | |
| ADR-0016 authentification | `workflow.test.sh` : jobs AWS liés à l'environnement et à `auth`, pas de `pull_request`, secrets uniquement en entrées de `configure-aws-credentials` (SHA identique à `aws-oidc`), OIDC prioritaire, secrets réservés à `dev` depuis `develop`, jeu incomplet refusé | une exécution sur `develop` avec les trois secrets déploie ; sans rien, annotation `Deployment skipped` |
| Revue 1 : rien à déployer | `workflow.test.sh` : `prepare` échoue sans service déployable ni frontend, ou si un `services/<nom>/` modifié n'a pas de manifeste | push de test sans manifeste : exécution rouge |

Raccordement à `task check` / `ci.yml` (cibles `test:unit`) : à faire dans une issue `role/ops`, le `Taskfile` et `ci.yml` étant hors du périmètre de EN-74.

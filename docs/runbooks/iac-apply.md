# Apply GitOps de l'infrastructure (`iac-apply`)

Workflow : `.github/workflows/iac-apply.yml` (EN-73, ADR-0009). Seule la CI applique l'infrastructure, hors `infra/bootstrap` (apply local par un humain). La cible `task apply` refuse de s'exécuter hors de GitHub Actions.

## Flux

| Événement | Environnement | Identité | Approbation |
|---|---|---|---|
| push sur `develop` touchant `infra/**` | `dev` | OIDC `sc-gha-apply-dev` si `AWS_APPLY_ROLE_ARN` est défini, sinon identifiants de session (workshop) | aucune |
| push sur `main` touchant `infra/**` (release `develop` → `main`) | `prod` | OIDC `sc-gha-apply-prod` uniquement (pas de déploiement `prod` pendant le workshop) | relecteur requis de l'environnement `prod` |
| `workflow_dispatch` lancé depuis `develop` (sans entrée) | `dev` | comme le push sur `develop` | aucune |

## Authentification (ADR-0016)

Chaque job de stack décide d'abord, dans l'étape « Check prerequisites », puis l'action `.github/actions/aws-auth` applique le mode choisi :

| Condition | Mode | Résultat |
|---|---|---|
| `AWS_APPLY_ROLE_ARN` non vide | OIDC (prioritaire) | assume le rôle |
| sinon, `dev`, depuis `develop`, et les trois secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` existent | secrets | identifiants de session de l'environnement `dev` |
| sinon, `dev` | aucun | succès, annotation « Apply skipped » |
| sinon, `prod` | aucun | échec « Apply refused » : `prod` n'utilise jamais les identifiants de session |

Un événement autre que `push` ou `workflow_dispatch` est refusé, et il n'y a pas de déclencheur `pull_request` : une PR ne reçoit jamais ces secrets. En mode secrets, `STATE_BUCKET` et `STATE_KMS_KEY_ARN` sont requis comme en mode OIDC. Les secrets ne sont jamais affichés ni placés dans un `env:` ; ils passent par les entrées de l'action. Les identifiants expirent : renouvellement dans `docs/runbooks/ci-variables.md`. Le plan de PR (`iac-plan`) est ignoré en mode secrets, le plan est calculé dans ce workflow.

Un lancement manuel n'est accepté que depuis `develop` : le job `target` échoue pour toute autre référence, `main` comprise, et le lancement n'a pas d'entrée qui permette de choisir l'environnement. Le groupe de concurrence d'un lancement refusé est unique, il ne peut donc pas retarder ou remplacer un apply de `prod` en attente. Le lancement manuel sert à rejouer un apply de `dev` après un échec ou un état modifié entre-temps. `prod` n'est appliqué que par un push (fusion de la release) sur `main`.

Le job `target` traduit la branche en environnement. Puis, dans l'ordre, un job par stack : `apply (foundation)`, puis `apply (platform)` (`needs`). Si `foundation` échoue, `platform` n'est pas lancé. Le contrat entre les deux stacks passe par SSM `/smartcampus/<env>/<stack>/<clé>`.

Chaque job de stack :

1. Vérifie les prérequis (variables de l'environnement, voir plus bas) ; sinon se termine en succès avec une annotation « Apply skipped ».
2. Pré-contrôle des providers, **sans identifiants AWS** (`task plan:preflight`, même script qu'`iac-plan`).
3. S'authentifie (`aws-auth`) : rôle apply de l'environnement par OIDC, ou identifiants de session de `dev` (voir « Authentification »).
4. `task plan ENV=<env> STACK=<stack> OUT=<fichier>` : plan écrit dans `$RUNNER_TEMP`, chiffré par OpenTofu (`encryption`, `enforced = true`).
5. « Plan summary » : avant l'apply, le résumé du job liste les comptes (création, mise à jour, remplacement, suppression) et, pour chaque ressource modifiée, l'action et l'adresse (limité à 200 lignes). Jamais de valeur d'attribut. Informatif : si la lecture du plan échoue, une annotation d'avertissement est émise et l'apply n'est pas bloqué.
6. `task apply ENV=<env> STACK=<stack> PLAN=<même fichier>` : applique ce fichier, rien d'autre.
7. Résumé du job : environnement, commit, PR, résultat des étapes et comptes (`Apply complete! Resources: x added, y changed, z destroyed.`). Aucune valeur d'attribut.
8. Supprime les fichiers temporaires.

## Plan figé (AC3)

Le plan appliqué est celui calculé dans le même job, quelques secondes plus tôt : il n'y a pas de second plan. `task apply` n'a pas de `-auto-approve` et échoue si le fichier de plan n'existe pas. Si le state a changé entre le plan et l'apply (autre apply, modification hors CI), OpenTofu rejette le plan (« Saved plan is stale »), le job échoue avec une annotation `Stale plan` et **rien n'est appliqué depuis ce plan**. Relancer le workflow (`Re-run failed jobs`, ou `workflow_dispatch` pour `dev`) calcule un nouveau plan. **Ne relancer (re-run ou dispatch) que le dernier run de la branche** : un job vérifie juste avant le plan que le commit du run est la tête actuelle de la branche (`git/ref/heads/<branche>`) et échoue avec `Stale run` sinon, car rejouer un vieux run planifierait et appliquerait un commit ancien, soit un retour arrière silencieux de l'environnement.

Choix plan et apply dans le même job (validé par SecOps) : le plan n'est jamais transmis d'un job à l'autre (pas d'artefact, même chiffré), ce qui évite de stocker ou de faire transiter un plan contenant des valeurs sensibles, et garantit que l'approbation de l'environnement `prod` précède le calcul du plan appliqué. C'est un écart assumé par rapport à la table de `.github/` (« upload encrypted plan artifact ») et à la lettre d'EN-73 : « plan revu » signifie ici le diff de release et le plan de `dev` du même commit (voir plus bas), pas un fichier de plan de `prod` relu avant l'apply. Le job n'a pas de séparation plan / apply gardée par une approbation, parce qu'un environnement GitHub dédié au plan (par exemple `prod-plan`) n'existe pas et ne peut pas être créé.

Toolchain : les jobs d'apply installent `task` et `tofu` avec `cache: "false"` (entrée `cache` de l'action `setup-toolchain`), pour qu'un cache écrit depuis une autre branche ne puisse pas alimenter un job qui détient `id-token: write`. Le binaire `mise` lui-même est épinglé par version et sha256 dans l'action (à mettre à jour ensemble).

Le fichier de plan et le state ne sont **jamais publiés** (pas d'artefact). Le texte du plan et de l'apply n'est jamais affiché : le journal ne contient que le code de sortie et au plus 5 lignes `Error:` d'OpenTofu.

## Approbation de `prod` (AC2)

L'environnement GitHub `prod` doit avoir (Settings → Environments → `prod`, voir `docs/runbooks/ci-variables.md`) :

- **Required reviewers** : au moins un relecteur désigné ;
- **Prevent self-review** activé ;
- **Deployment branches** limitées à `main` : c'est la vraie protection du rôle `sc-gha-apply-prod`, car son `sub` OIDC prouve l'environnement, pas la branche (ADR-0012, risque 1) ;
- `dev` : branches de déploiement limitées à `develop`.

État actuel : les environnements GitHub `prod` (branche de déploiement `main` uniquement, relecteur requis) et `dev` (`develop` uniquement) existent et sont configurés ainsi. Cette règle de branche est la garde réelle contre un workflow modifié sur une autre branche : le contrôle du job `target` est dans le workflow, donc contournable par une copie éditée, alors que la règle d'environnement est évaluée par GitHub avant le job.

L'approbation est demandée **avant le démarrage** de chaque job `apply` de `prod`. Le plan que le job calcule est donc celui qui est appliqué, et il n'y a pas de plan « approuvé puis recalculé ».

Conséquences à connaître :

- Il y a **deux demandes d'approbation** pour une release qui touche `infra/` : une pour `foundation`, une pour `platform`. Le relecteur de `platform` voit déjà le résultat de `foundation` dans son résumé.
- Le relecteur ne voit pas le plan de `prod` avant d'approuver (le rôle plan n'a pas accès au state de `prod`, ADR-0012). **L'approbation couvre** : (1) le diff de la release dans la **PR `develop` → `main`** (code, `CHANGELOG`) ; (2) le **plan de `dev`** commenté par `iac-plan` sur les PR vers `develop` ; (3) l'**apply de `dev` du même commit**, déjà passé, dont le résumé de job (section « Plan summary » et comptes) montre ce qui a été appliqué. Avant d'approuver, vérifier que le job `iac-apply` de `dev` de ce commit est vert.
- Dans `prod`, la section « Plan summary » du résumé de job (actions et adresses, sans valeur) est écrite **avant** l'apply, mais elle est informative : il n'y a pas de seconde approbation entre le plan et l'apply. Une divergence entre `dev` et `prod` (state différent, dérive) n'est donc visible qu'une fois l'apply lancé ; les garde-fous `prevent_destroy` et `deletion_protection` bloquent le plan des suppressions les plus graves. Si le résumé montre un écart inattendu pendant l'apply, annuler le run n'est pas recommandé (un apply interrompu laisse le state verrouillé et partiellement appliqué, voir « Échec d'un apply ») : corriger par une PR de revert.
- Les variables `AWS_APPLY_ROLE_ARN`, `STATE_BUCKET` et `STATE_KMS_KEY_ARN` sont lues dans l'environnement : tant que `AWS_APPLY_ROLE_ARN` est vide, les jobs se terminent en succès avec une annotation, mais l'approbation de `prod` est tout de même demandée (elle précède le job).

## Concurrence (AC4)

Groupe `iac-apply-dev` ou `iac-apply-prod`, `cancel-in-progress: false` : un apply en cours n'est jamais annulé. Un run en attente est remplacé par un run plus récent en attente (il applique le commit le plus récent, qui contient les précédents). Le verrou natif S3 du state (`use_lockfile`, ADR-0011) protège en plus contre un apply lancé hors de ce workflow.

## Traçabilité (AC5)

Le résumé de chaque job indique l'environnement, le SHA du commit, la PR (extraite du message de fusion `(#n)` ou `Merge pull request #n`) et l'issue de chaque étape. L'onglet Deployments du dépôt liste les déploiements par environnement.

## Tests (EN-73-AC1 à AC5)

`tests/ci/iac-apply.test.sh` vérifie le contrat du workflow : analyse statique du fichier, plus exécution du vrai script du job `target` pour chaque couple (événement, référence). Pas de réseau, pas d'AWS. Il utilise `yq` (mikefarah v4) pour quelques contrôles structurels s'il est dans le `PATH`, sinon `grep`. Il tourne dans le job `lint` de `ci.yml` (étape « Workflow contract tests », si le fichier existe) ; le lancer aussi à la main après toute modification de `iac-apply.yml`. Il exécute aussi le vrai script de l'étape « Check prerequisites » pour chaque combinaison de mode, d'environnement et de branche (ADR-0016).

```
bash tests/ci/iac-apply.test.sh
```

| Critère | Ce qui est vérifié |
|---|---|
| EN-73-AC1 | déclencheurs `develop`/`main`, `develop` → `dev` (push et lancement manuel), `foundation` puis `platform`, rôle apply de l'environnement, repli de région `us-east-1`, choix du mode (OIDC prioritaire, secrets, aucun), variables d'état requises, `TF_VAR_admin_principal_arns` |
| EN-73-AC2 | `main` → `prod` (push uniquement), lancement manuel refusé hors `develop`, jobs d'apply liés à l'environnement résolu, `target` sans environnement ni OIDC, `id-token: write` limité aux deux jobs d'apply, identifiants de session refusés hors `develop` et pour `prod`, aucun apply sur `pull_request`, secrets lus uniquement comme entrées de `aws-auth` |
| EN-73-AC3 | un seul chemin de fichier de plan pour `OUT` et `PLAN`, plan et apply dans le même job, aucun artefact ni cache, pas de `-auto-approve`, plan périmé et run périmé refusés, résumé du plan sans valeur et avant l'apply |
| EN-73-AC4 | groupe de concurrence par environnement, `cancel-in-progress: false`, groupe unique pour un run refusé, `timeout-minutes` sur chaque job |
| EN-73-AC5 | environnement, commit, PR, résultats du plan et de l'apply dans le résumé de chaque job, résumé écrit même en cas d'échec, message de commit passé par `env` |

## Prérequis

Voir `docs/runbooks/ci-variables.md`.

- Mode OIDC : variable `AWS_APPLY_ROLE_ARN` dans l'environnement.
- Mode workshop (ADR-0016) : secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` de l'environnement `dev` (branches de déploiement : `develop` seule), `AWS_APPLY_ROLE_ARN` vide.
- Dans les deux modes : variables `STATE_BUCKET`, `STATE_KMS_KEY_ARN` (et `AWS_REGION` en option) au niveau du dépôt ou de l'environnement, et `TF_VAR_admin_principal_arns` (liste JSON, stack `foundation`). Si des identifiants sont configurés mais pas `STATE_BUCKET` ou `STATE_KMS_KEY_ARN`, le job échoue.

`AWS_REGION` : valeur de repli `us-east-1` dans les deux jobs d'apply (région de l'endpoint STS et de la session du rôle). La région du backend du state est celle de `infra/envs/<env>/backend.hcl` et n'en dépend pas.

Tant qu'aucun identifiant n'est configuré pour `dev` (ni rôle OIDC, ni les trois secrets de session, par exemple après expiration), le workflow reste vert avec l'annotation « Apply skipped ». Les stacks `foundation` et `platform` ne sont par ailleurs pas toutes couvertes par les politiques du rôle apply (ADR-0012, risque 5) : un apply qui y crée des services non couverts échouera en `AccessDenied` tant que les politiques ne sont pas étendues.

## Échec d'un apply

Un apply interrompu laisse un état partiellement appliqué, cohérent avec le state. C'est le cas notamment si la session du workshop expire en cours d'apply : renouveler les trois secrets (`docs/runbooks/ci-variables.md`) puis relancer le dernier run. Ne pas modifier le state à la main. Relancer le workflow : le nouveau plan reprend ce qui reste. Si le verrou du state reste posé après un job tué, un administrateur du bootstrap le supprime (`tofu force-unlock`, hors CI, après vérification qu'aucun apply ne tourne).

## Retour arrière (rollback)

Il n'y a pas de rollback automatique : on **annule par le code**.

1. Ouvrir une PR de revert (`git revert <commit>`) vers `develop`, plan de `dev` commenté, fusion : `dev` converge vers l'état précédent.
2. Pour `prod`, le revert suit le chemin normal `develop` → `main` (release PR), avec approbation.
3. Cas d'urgence en `prod` : revert directement dans une PR vers `develop`, puis release immédiate.

Limites : un revert qui supprime une ressource la détruit (tables, buckets, clés KMS) ; les protections `prevent_destroy` et `deletion_protection` bloquent volontairement le plan, il faut alors une PR dédiée qui les lève avec un ADR ou une note de risque. Les données détruites ne sont pas restaurées par un revert (PITR et versioning, voir les runbooks de données).

## Dérive

Une modification hors CI est écrasée au prochain apply de la stack concernée, mais seulement si un push touche `infra/**`. La détection planifiée (`tofu plan -detailed-exitcode` nocturne, issue étiquetée `drift`) est prévue dans EN-75, pas dans ce workflow.

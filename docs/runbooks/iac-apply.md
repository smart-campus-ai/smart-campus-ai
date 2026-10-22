# Apply GitOps de l'infrastructure (`iac-apply`)

Workflow : `.github/workflows/iac-apply.yml` (EN-73, ADR-0009). Seule la CI applique l'infrastructure, hors `infra/bootstrap` (apply local par un humain). La cible `task apply` refuse de s'exécuter hors de GitHub Actions.

## Flux

| Événement | Environnement | Rôle assumé (OIDC) | Approbation |
|---|---|---|---|
| push sur `develop` touchant `infra/**` | `dev` | `sc-gha-apply-dev` | aucune |
| push sur `main` touchant `infra/**` (release `develop` → `main`) | `prod` | `sc-gha-apply-prod` | relecteur requis de l'environnement `prod` |
| `workflow_dispatch` (entrée `env`, uniquement `dev`) | `dev` | `sc-gha-apply-dev` | aucune |

Un lancement manuel n'est accepté que depuis `develop` : le job `target` échoue pour toute autre branche. Il sert à rejouer un apply de `dev` après un échec ou un état modifié entre-temps. `prod` n'est appliqué que par une fusion sur `main`.

Le job `target` traduit la branche en environnement. Puis, dans l'ordre, un job par stack : `apply (foundation)`, puis `apply (platform)` (`needs`). Si `foundation` échoue, `platform` n'est pas lancé. Le contrat entre les deux stacks passe par SSM `/smartcampus/<env>/<stack>/<clé>`.

Chaque job de stack :

1. Vérifie les prérequis (variables de l'environnement, voir plus bas) ; sinon se termine en succès avec une annotation « Apply skipped ».
2. Pré-contrôle des providers, **sans identifiants AWS** (`task plan:preflight`, même script qu'`iac-plan`).
3. Assume le rôle apply de l'environnement par OIDC.
4. `task plan ENV=<env> STACK=<stack> OUT=<fichier>` : plan écrit dans `$RUNNER_TEMP`, chiffré par OpenTofu (`encryption`, `enforced = true`).
5. `task apply ENV=<env> STACK=<stack> PLAN=<même fichier>` : applique ce fichier, rien d'autre.
6. Résumé du job : environnement, commit, PR, résultat des étapes et comptes (`Apply complete! Resources: x added, y changed, z destroyed.`). Aucune valeur d'attribut.
7. Supprime les fichiers temporaires.

## Plan figé (AC3)

Le plan appliqué est celui calculé dans le même job, quelques secondes plus tôt : il n'y a pas de second plan. `task apply` n'a pas de `-auto-approve` et échoue si le fichier de plan n'existe pas. Si le state a changé entre le plan et l'apply (autre apply, modification hors CI), OpenTofu rejette le plan (« Saved plan is stale »), le job échoue avec une annotation `Stale plan` et **rien n'est appliqué depuis ce plan**. Relancer le workflow (`Re-run failed jobs`, ou `workflow_dispatch` pour `dev`) calcule un nouveau plan. **Ne relancer (re-run ou dispatch) que le dernier run de la branche** : un job vérifie juste avant le plan que le commit du run est la tête actuelle de la branche (`git/ref/heads/<branche>`) et échoue avec `Stale run` sinon, car rejouer un vieux run planifierait et appliquerait un commit ancien, soit un retour arrière silencieux de l'environnement.

Choix plan et apply dans le même job : le plan n'est jamais transmis d'un job à l'autre (pas d'artefact, même chiffré), ce qui évite de stocker ou de faire transiter un plan contenant des valeurs sensibles, et garantit que l'approbation de l'environnement `prod` précède le calcul du plan appliqué.

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
- Le relecteur ne voit pas le plan de `prod` avant d'approuver (le rôle plan n'a pas accès au state de `prod`, ADR-0012). Ce qu'il revoit : la **PR vers `main`** (diff de la release, `CHANGELOG`), et le **plan de `dev`** commenté sur les PR vers `develop` par `iac-plan`. Les comptes de `prod` apparaissent dans le résumé du job, après l'apply.
- Les variables `AWS_APPLY_ROLE_ARN`, `STATE_BUCKET` et `STATE_KMS_KEY_ARN` sont lues dans l'environnement : tant que `AWS_APPLY_ROLE_ARN` est vide, les jobs se terminent en succès avec une annotation, mais l'approbation de `prod` est tout de même demandée (elle précède le job).

## Concurrence (AC4)

Groupe `iac-apply-dev` ou `iac-apply-prod`, `cancel-in-progress: false` : un apply en cours n'est jamais annulé. Un run en attente est remplacé par un run plus récent en attente (il applique le commit le plus récent, qui contient les précédents). Le verrou natif S3 du state (`use_lockfile`, ADR-0011) protège en plus contre un apply lancé hors de ce workflow.

## Traçabilité (AC5)

Le résumé de chaque job indique l'environnement, le SHA du commit, la PR (extraite du message de fusion `(#n)` ou `Merge pull request #n`) et l'issue de chaque étape. L'onglet Deployments du dépôt liste les déploiements par environnement.

## Prérequis

Variables GitHub (aucun secret), voir `docs/runbooks/ci-variables.md` : `AWS_APPLY_ROLE_ARN` dans chaque environnement ; `STATE_BUCKET`, `STATE_KMS_KEY_ARN` (et `AWS_REGION` en option) au niveau du dépôt ou de l'environnement. Si `AWS_APPLY_ROLE_ARN` est défini mais pas l'une des deux autres, le job échoue.

Tant que le bootstrap n'est pas appliqué, le workflow reste vert avec l'annotation « Apply skipped ». Les stacks `foundation` et `platform` ne sont par ailleurs pas toutes couvertes par les politiques du rôle apply (ADR-0012, risque 5) : un apply qui y crée des services non couverts échouera en `AccessDenied` tant que les politiques ne sont pas étendues.

## Échec d'un apply

Un apply interrompu laisse un état partiellement appliqué, cohérent avec le state. Ne pas modifier le state à la main. Relancer le workflow : le nouveau plan reprend ce qui reste. Si le verrou du state reste posé après un job tué, un administrateur du bootstrap le supprime (`tofu force-unlock`, hors CI, après vérification qu'aucun apply ne tourne).

## Retour arrière (rollback)

Il n'y a pas de rollback automatique : on **annule par le code**.

1. Ouvrir une PR de revert (`git revert <commit>`) vers `develop`, plan de `dev` commenté, fusion : `dev` converge vers l'état précédent.
2. Pour `prod`, le revert suit le chemin normal `develop` → `main` (release PR), avec approbation.
3. Cas d'urgence en `prod` : revert directement dans une PR vers `develop`, puis release immédiate.

Limites : un revert qui supprime une ressource la détruit (tables, buckets, clés KMS) ; les protections `prevent_destroy` et `deletion_protection` bloquent volontairement le plan, il faut alors une PR dédiée qui les lève avec un ADR ou une note de risque. Les données détruites ne sont pas restaurées par un revert (PITR et versioning, voir les runbooks de données).

## Dérive

Une modification hors CI est écrasée au prochain apply de la stack concernée, mais seulement si un push touche `infra/**`. La détection planifiée (`tofu plan -detailed-exitcode` nocturne, issue étiquetée `drift`) est prévue dans EN-75, pas dans ce workflow.

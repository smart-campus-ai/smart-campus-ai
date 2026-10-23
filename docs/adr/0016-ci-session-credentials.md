# 0016 — Identité CI du workshop : identifiants de session en secrets de l'environnement `dev`

- Statut : Accepté
- Date : 2026-10-23
- Décideurs : OPS

## Contexte

EN-73 (issue #49) : la CI applique l'infrastructure (ADR-0009). ADR-0012 prévoit une authentification par OIDC GitHub, avec un rôle plan et un rôle apply par environnement, créés par `infra/bootstrap`. Pour le workshop, l'OPS a décidé de **ne pas utiliser GitHub OIDC**. La CI s'authentifie avec les **identifiants de session** du compte workshop (clé d'accès, clé secrète, jeton de session), temporaires et fournis par Workshop Studio.

Cette décision déroge à deux règles du steering (« GitHub → AWS uniquement par OIDC », « jamais de secrets ni de clés » dans `cicd`) ; elle est donc bornée par cet ADR. ADR-0012 reste valable pour une vraie production et n'est pas remplacé : ce document le complète.

## Facteurs de décision

- Sécurité : aucune exposition des identifiants à du code de pull request ou de fork.
- Délai : le workshop ne laisse pas la place d'un bootstrap OIDC complet (fournisseur, rôles, boundaries).
- Réversibilité : revenir à OIDC doit être un changement de configuration, pas de workflow.
- Durée de vie : les identifiants de session expirent.

## Options considérées

1. OIDC uniquement (ADR-0012), après apply du bootstrap.
2. Identifiants de session en secrets du dépôt.
3. Identifiants de session en secrets de l'environnement GitHub `dev`, avec OIDC prioritaire si le rôle est configuré.

## Décision

Option 3. Règles :

- **Environnement `dev` seul.** Les secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` et `AWS_SESSION_TOKEN` sont des secrets de l'environnement GitHub `dev`, avec la variable `AWS_REGION=us-east-1`. Les jobs AWS tournent uniquement avec `environment: dev`, dont la politique de branches de déploiement n'autorise que `develop`. Un secret d'environnement est inaccessible à toute autre référence, donc aux PR.
- **Jamais sur `pull_request`.** Ni apply, ni déploiement. Jamais pour une PR de fork. `iac-apply` n'a pas de déclencheur `pull_request` et son contrôle d'entrée refuse tout autre événement que `push` et `workflow_dispatch`.
- **Plan de PR.** Les secrets de l'environnement `dev` ne sont pas disponibles sur une référence de PR : en mode secrets (`AWS_PLAN_ROLE_ARN` vide), le job `iac-plan` est ignoré avec une annotation. Le plan s'exécute dans le job d'apply sur `develop` (plan figé, appliqué tel quel).
- **Priorité OIDC.** Si `vars.AWS_APPLY_ROLE_ARN` est non vide, l'OIDC (`role-to-assume`) l'emporte. Sinon, mode secrets (`dev` depuis `develop` uniquement). Sinon, le job est ignoré avec une annotation (`dev`) ou échoue (`prod`).
- **`prod` : OIDC uniquement, non déployé pendant le workshop.** Les identifiants de session ne sont jamais utilisés pour `prod`, même s'ils existent dans l'environnement.
- **Pas de fuite.** Aucun secret n'est affiché ni placé dans un `env:`. Ils transitent seulement par les entrées de `aws-actions/configure-aws-credentials` (`aws-access-key-id`, `aws-secret-access-key`, `aws-session-token`), via l'action composite `.github/actions/aws-auth` (épinglée par SHA, comme `aws-oidc` qui reste utilisée par `iac-plan`). Le contrôle d'entrée ne reçoit qu'un booléen « les trois secrets existent ». L'action masque les valeurs et les exporte aux étapes suivantes, ce dont le SDK AWS a besoin ; les variables de requête du jeton OIDC restent vidées dans toutes les étapes qui exécutent du HCL.
- **Expiration.** Les identifiants expirent. Le renouvellement (l'OPS recopie les trois secrets depuis Workshop Studio) est décrit dans `docs/runbooks/ci-variables.md`.

## Conséquences

- Positives : la CI déploie sans bootstrap OIDC ; le retour à OIDC ne demande que de renseigner `AWS_APPLY_ROLE_ARN` ; les protections du plan figé, du pré-contrôle des providers et du contrôle de tête de branche restent identiques.
- Négatives / dette : plus de plan commenté sur les PR en mode secrets ; un apply peut échouer à mi-course si la session expire (état partiellement appliqué, verrou à lever, voir `docs/runbooks/iac-apply.md`) ; renouvellement manuel à chaque expiration ; un test automatisé du contrôle d'entrée (`tests/ci/iac-apply.test.sh`) remplace la garantie de confiance `sub` d'OIDC.

## Impact sécurité

- Les identifiants portent les droits du principal du workshop, a priori plus larges que le rôle apply plafonné par des boundaries d'ADR-0012 (moindre privilège, isolation dev / prod). **À confirmer par l'OPS** ; ce plafond n'existe plus en mode secrets.
- Les secrets sont lisibles par tout code exécuté dans un job de l'environnement `dev` : le HCL d'`infra/` et les actions tierces. Les garde-fous existants s'appliquent (providers vérifiés avant les identifiants, outils installés avant les identifiants, pas de cache dans les jobs d'apply), mais une fois fusionné sur `develop`, le code est de confiance. La règle de fusion actuelle (0 approbation) ne l'arrête pas : le risque est accepté pour la durée du workshop, limité par la courte durée de vie des identifiants.
- Ni les secrets de dépôt ni ceux de `prod` ne sont utilisés. Les secrets de l'environnement sont masqués dans les journaux.
- Détection : pas d'alerte propre aux identifiants de session (CloudTrail du compte workshop).

## Impact coût

Aucun coût direct. Coût d'exploitation : un renouvellement manuel des trois secrets à chaque expiration de session.

## Liens

- Issue #49 (EN-73)
- ADR [0009](0009-gitops-no-local-apply.md), [0010](0010-base-pinned-gate-files.md), [0012](0012-github-oidc-ci-identity.md), [0013](0013-workshop-region-us-east-1.md)
- `docs/runbooks/ci-variables.md`, `docs/runbooks/iac-apply.md`, `.github/actions/aws-auth/action.yml`

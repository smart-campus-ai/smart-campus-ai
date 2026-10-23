# 0014 — Contraintes IAM du compte workshop : fournisseur OIDC et permissions boundaries

- Statut : Accepté
- Date : 2026-10-23
- Décideurs : OPS, AS

## Contexte

Le compte workshop (762233769579) n'est utilisable que via `WSParticipantRole`. Ses politiques gérées, lues dans le compte (source de vérité), sont `PowerUserAccess`, `ws-default-policy` et `console-iam-policy-0` :

| Autorisé (`Allow`) | Non autorisé (aucun `Allow`) | Refusé explicitement (`Deny`) |
|---|---|---|
| `iam:CreateRole`, `DeleteRole`, `UpdateAssumeRolePolicy`, `PassRole`, `PutRolePolicy`, `AttachRolePolicy` sur `role/*` | `iam:CreateOpenIDConnectProvider` | utilisateurs et groupes IAM, clés d'accès |
| `iam:CreatePolicy*`, `SetDefaultPolicyVersion` sur `policy/*` | `iam:PutRolePermissionsBoundary` | toute action hors `us-east-1` (ADR-0013) |
| `iam:CreateServiceLinkedRole` | `iam:DeleteRolePermissionsBoundary` | |

Deux décisions acceptées ne sont donc pas applicables telles quelles :

1. **Pas de fournisseur OIDC GitHub.** ADR-0012 crée `token.actions.githubusercontent.com` dans le bootstrap. Sans lui, la CI ne peut pas s'authentifier, et la règle « jamais de clé d'accès dans GitHub » (`security.md`) interdit le contournement par clé longue durée (de toute façon refusé par le `Deny`).
2. **Pas de permissions boundary.** `iam:CreateRole` avec le paramètre `PermissionsBoundary` exige `iam:PutRolePermissionsBoundary`. L'invariant « boundary projet sur chaque rôle » (`security.md`, ADR-0012) ne peut pas être tenu dans ce compte : ni pour les rôles CI (`sc-ci-boundary`), ni pour les rôles workload (`sc-<env>-workload-boundary`).

Point connexe : le rôle CloudWatch d'API Gateway (`aws_api_gateway_account`) est un réglage unique par compte et par région, partagé par dev et prod (ADR-0012, risque 3).

Exigences concernées : EN-13, ADR-0009 (GitOps), ADR-0011, ADR-0012, tous les modules qui créent des rôles (`lambda-service`, `sla-scheduler`, `knowledge-base`, `attachments-bucket`).

## Facteurs de décision

- Sécurité : aucune clé longue durée, moindre privilège, pas d'escalade par création de rôle.
- GitOps (ADR-0009) : aucun apply local hors bootstrap.
- Effort et délai : l'atelier doit déployer sans attendre indéfiniment les organisateurs.
- Réversibilité : retour aux invariants complets sans réécriture dès que le compte le permet (ou sur un compte réel).

## Options considérées

1. **(A) Les organisateurs lèvent les deux blocages** : fournisseur OIDC GitHub pré-créé **et** boundaries rendues possibles (délégation de `iam:PutRolePermissionsBoundary` ou rôles CI pré-créés avec leur boundary). Le fournisseur seul ne suffit pas : `WSParticipantRole` ne peut pas créer les rôles `sc-gha-*` avec `sc-ci-boundary`. Ce cas partiel relève de B.
2. **(B) Boundaries optionnelles**, garde-fous déplacés dans les politiques d'identité, exception workshop bornée, réversible par variable.
3. **(C) Applies locaux** de toute la plateforme depuis le poste OPS avec le profil workshop.

| Critère | A | B | C |
|---|---|---|---|
| Sécurité | Complète (ADR-0012 intact) | Plafond perdu, compensé par des politiques d'identité à `Deny` explicites, tags et détection | Faible : identifiants humains larges, pas de revue, pas de traçabilité CI |
| Effort | Faible pour nous, dépend des organisateurs | Moyen : variables nullables, statements conditionnels, check Checkov, tests | Nul à court terme |
| Réversibilité | Totale | Totale : une valeur de variable par environnement | Mauvaise : dérive du state, habitudes hors GitOps |
| Conformité aux ADR | Conforme | Écart documenté à `security.md` (boundaries) | Viole ADR-0009 |

## Décision

**A en priorité, B en repli, jamais C.**

**Acceptation (OPS, issue #98) : B est retenue** pour l'atelier, avec le plafond du 2026-10-31. Décision OPS connexe : pas de fournisseur OIDC GitHub (ADR 0016, autre PR). Conséquences dans le code : le bootstrap ne crée ni le fournisseur OIDC ni les rôles CI (`create_oidc_provider = false` et `create_ci_roles = false` par défaut, le module `github-oidc` n'est alors pas instancié) ; dans les stacks, `enable_permissions_boundaries` vaut `false` par défaut et `true` rétablit l'invariant complet.

### A — demande aux organisateurs (issue #98)

A n'est retenue que si les organisateurs fournissent **les deux** éléments suivants :

1. le fournisseur OIDC `https://token.actions.githubusercontent.com` (audience `sts.amazonaws.com`), référencé par `create_oidc_provider = false` et `existing_oidc_provider_arn` (déjà prévus par ADR-0012) ;
2. **et l'un des deux** :
   - (a) l'ajout à `WSParticipantRole` de `iam:CreateRole` et `iam:PutRolePermissionsBoundary` sous condition `iam:PermissionsBoundary` ∈ {`sc-ci-boundary`, `sc-dev-workload-boundary`, `sc-prod-workload-boundary`} : le bootstrap crée alors les rôles CI avec leur boundary, comme prévu ;
   - (b) les politiques `sc-ci-boundary` et `sc-<env>-workload-boundary` et les trois rôles `sc-gha-plan`, `sc-gha-apply-dev`, `sc-gha-apply-prod` pré-créés, boundary attachée, à partir du JSON généré par le module `github-oidc` (sortie à ajouter) ; le bootstrap les référence (`create_ci_roles = false`, entrée à ajouter) et n'y attache que les politiques d'identité, ce que `AttachRolePolicy` sur `role/*` permet.

Dans les deux cas ADR-0012 s'applique sans changement : les rôles apply créent les rôles workload avec leur boundary grâce à leur propre politique d'identité. Le fournisseur OIDC seul, sans (a) ni (b), bascule en B.

### B — repli si les boundaries restent impossibles

Changements de code requis (tous derrière une seule variable par stack, `enable_permissions_boundaries`, `false` par défaut pendant l'atelier) :

- **Entrées nullables.** `permissions_boundary_arn` devient `nullable = true`, sans valeur par défaut, dans `lambda-service`, `sla-scheduler`, `knowledge-base`, `attachments-bucket` et pour le rôle CloudWatch d'API Gateway du bootstrap ; `aws_iam_role` garde toujours l'argument `permissions_boundary = var.permissions_boundary_arn`. Les stacks passent `null` seulement si `enable_permissions_boundaries = false`.
- **Module `github-oidc`.** Avec `enable_permissions_boundaries = false` : rôles CI créés sans `permissions_boundary`, boundaries non attachées. Les statements d'apply d'ADR-0012 deviennent conditionnels (`dynamic`) :
  - `RoleCreateWithWorkloadBoundary` → `RoleCreateWithEnvironmentTag` : `iam:CreateRole` seul (sans `iam:PutRolePermissionsBoundary`) sur `role/sc-<env>-*`, condition `aws:RequestTag/Environment = <env>` à la place de `iam:PermissionsBoundary` ;
  - `RolePoliciesWithWorkloadBoundary` → `RolePoliciesWithEnvironmentTag` : mêmes actions, condition `aws:ResourceTag/Environment = <env>` ;
  - nouveau `DenyNonProjectManagedPolicies` : `Deny` de `iam:AttachRolePolicy` si `iam:PolicyARN` n'est pas `ArnLike` `policy/sc-<env>-*` ni dans une liste fermée `allowed_managed_policy_arns` (vide par défaut) : interdit `AdministratorAccess` et `PowerUserAccess` ;
  - nouveau `DenyEnvironmentRetag` : `Deny` de `iam:TagRole`/`UntagRole` sur la clé `Environment` (`aws:TagKeys`) ;
  - inchangés : `RoleManage`, `PolicyManage`, `PassRoleToPlatformServices` (`iam:PassedToService`).
- **Garde-fous de `sc-ci-boundary` déplacés.** Les `Deny` de la boundary CI (`DenyCiRoleTampering`, `DenyCiPolicyTampering`, `DenyOidcProviderTampering`, `DenyLongLivedCredentials`, `DenyAccountLevelServices`, `DenyBoundaryRemoval`) sont copiés dans une politique d'identité `sc-gha-guardrails` attachée aux trois rôles CI. Un `Deny` d'identité a le même effet qu'un `Deny` de boundary ; seule la notion de plafond (tout ce qui n'est pas listé est refusé) est perdue.
- **Contrôle de portée.** Précondition dans le bootstrap et dans chaque stack : `enable_permissions_boundaries = false` exige que `data.aws_caller_identity` soit dans `boundary_exception_account_ids` (fixé dans `envs/<env>/*.tfvars` au seul compte 762233769579) et que `plantimestamp()` soit avant `boundary_exception_expires` (date de fin de l'atelier). Hors de ce compte ou après cette date, le plan échoue.
- **Checkov CKV_SC_3** (à créer dans `policies/`, absent aujourd'hui) : échoue si un `aws_iam_role` n'a pas d'argument `permissions_boundary` ou s'il vaut littéralement `null`. Les modules passent toujours la variable, donc le check reste bloquant sans skip. Si un skip devient inévitable, seul ce format est admis, listé dans la description de PR : `# checkov:skip=CKV_SC_3: ADR-0014 workshop exception, account without iam:PutRolePermissionsBoundary, expires <date>`.
- **Tests (`tofu test`, mocks).** `github-oidc` dans les deux modes : avec boundaries, les assertions actuelles restent ; sans, assertions qu'aucun statement ne porte `iam:PermissionsBoundary`, que les conditions de tag et `DenyNonProjectManagedPolicies` sont présentes, que `sc-gha-guardrails` est attachée aux trois rôles et contient tous les `Deny` de `sc-ci-boundary`. Modules de rôles : `null` ⇒ pas de boundary, ARN ⇒ boundary. Préconditions : `expect_failures` pour un compte hors liste et une date dépassée. Test du check CKV_SC_3 sur des fixtures dans `policies/`.
- **Détection.** IAM Access Analyzer (accès externe et inutilisé) via le module de baseline, avec alarme ; alarme CloudTrail sur `CreateRole`, `AttachRolePolicy`, `PutRolePolicy`, `UpdateAssumeRolePolicy` hors rôles `sc-gha-apply-*`.
- **Réversibilité.** Retour aux invariants complets en passant `enable_permissions_boundaries = true` et l'ARN des boundaries dans les tfvars : un plan met à jour les rôles en place (ajout de la boundary, retour des conditions `iam:PermissionsBoundary`), sans recréation de ressource. Le code de B est ensuite supprimé (variable, statements conditionnels, préconditions).

À vérifier dans le compte avant B : si aucune SCP ne refuse `iam:PutRolePermissionsBoundary` aux rôles créés par nous (non lisible avec `WSParticipantRole`), les rôles apply pourraient garder les boundaries workload ; seuls les rôles CI en seraient privés. Ce sous-cas réduit l'exception et sera noté dans l'issue #98.

### Exception à l'invariant `security.md` (B uniquement)

L'invariant « every IAM role created by OpenTofu has the project permissions boundary attached; the CI apply role can only create roles that carry it » est suspendu :

- portée : compte workshop 762233769579 uniquement, environnements `sc-dev` et `sc-prod` de l'atelier, jusqu’à `boundary_exception_expires`, **plafonné au 2026-10-31** (fin de l’atelier ; validation : la valeur ne peut pas dépasser cette date, et une précondition refuse tout apply après expiration) ; tout autre compte reste soumis à l'invariant, imposé par la précondition ;
- contrôles compensatoires : conditions de tag `Environment`, `Deny` des politiques gérées hors projet, `sc-gha-guardrails`, `iam:PassedToService`, revue de plan en PR, Access Analyzer, alarmes CloudTrail, données fictives (ADR-0013) ;
- tests : ceux listés ci-dessus, exécutés par `task check`.

Cette ADR est la référence de l'exception ; `security.md` et ADR-0012 y renvoient.

### Commun à A et B
- **Rôle CloudWatch d'API Gateway** : créé une seule fois dans le bootstrap (`aws_iam_role` + `aws_api_gateway_account`), possible avec `iam:CreateRole` et `iam:PassRole`. Les stacks ne le gèrent pas : deux stacks qui écrivent `aws_api_gateway_account` s'écraseraient. Le rôle utilise la politique gérée `AmazonAPIGatewayPushToCloudWatchLogs`, avec une confiance `apigateway.amazonaws.com` conditionnée par `aws:SourceAccount`.
- **C est exclu** : identifiants humains très larges (`PowerUserAccess`) utilisés pour chaque déploiement, aucune revue de plan, aucune trace d'apply liée à un commit. Le bootstrap reste le seul apply local (ADR-0009, ADR-0011).

Piliers Well-Architected : sécurité (SEC02/SEC03 : identités temporaires, moindre privilège, garde-fous en repli), fiabilité (déploiements reproductibles par la CI), excellence opérationnelle (retour arrière par une variable).

## Conséquences

- Positives : la CI reste sans secret ; le code garde la boundary comme cible ; l'écart est explicite, limité au compte workshop et réversible.
- Négatives / dette :
  - dépendance à un tiers pour A ; tant que le fournisseur OIDC n'existe pas, aucune stack ne s'applique par la CI ;
  - A (b) ajoute au module `github-oidc` une sortie JSON des boundaries et une entrée `create_ci_roles` ;
  - avec B, un rôle apply peut créer des rôles `sc-<env>-*` sans plafond : la séparation dev / prod d'ADR-0012 perd une barrière (la boundary workload par environnement) et repose sur le préfixe, le tag `Environment` et les `Deny` d'identité ;
  - B ajoute une variable, des statements conditionnels, des préconditions et des tests à maintenir ; tout est supprimé au retour des boundaries ;
  - `security.md` et ADR-0012 reçoivent un renvoi vers cette ADR si B est retenu (même PR que le code de B).

## Impact sécurité

A : aucun changement de surface. B : perte du plafond sur les rôles créés par la CI et sur les rôles CI eux-mêmes. Risques résiduels : une politique inline (`PutRolePolicy`) écrite par un rôle apply sur un rôle `sc-<env>-*` n'est bornée que par la revue de plan et les tests des modules ; le risque 9 d'ADR-0012 (confiance OIDC/SAML hostile) n'est plus bloqué par `aws:FederatedProvider` et n'est que détecté (Access Analyzer accès externe). `AdministratorAccess` et les politiques gérées hors projet sont bloquées par `DenyNonProjectManagedPolicies`. Les rôles CI ne peuvent toujours pas modifier leur confiance ni leurs politiques (`sc-gha-guardrails`). Les données restent fictives (ADR-0013) et la précondition empêche l'exception hors du compte workshop : risque acceptable pour l'atelier seulement. Le rôle CloudWatch d'API Gateway reste partagé entre environnements (risque connu).

## Impact coût

Aucun coût direct (IAM, STS, fournisseur OIDC gratuits). Access Analyzer accès externe gratuit ; l'analyse des accès inutilisés est facturée par rôle analysé et par mois (quelques dollars à l'échelle du projet), désactivable. Coût d'effort : environ un jour pour B (variables, statements conditionnels, préconditions, check Checkov, tests), une demi-journée pour A (b).

## Liens

- Issue #98, EN-13
- ADR [0009](0009-gitops-no-local-apply.md), [0011](0011-state-backend-bootstrap.md), [0012](0012-github-oidc-ci-identity.md), [0013](0013-workshop-region-us-east-1.md)
- `.kiro/steering/security.md` (Identity and access), `.kiro/steering/iac.md`, `infra/modules/github-oidc/README.md`

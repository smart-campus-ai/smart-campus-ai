# 0009 — GitOps : aucun apply local hors bootstrap

- Statut : Accepté
- Date : 2026-10-22
- Décideurs : AS, OPS, QE

## Contexte

NFR-01 (ex-RF02) exige que tout changement d'infrastructure soit tracé (issue ↔ PR ↔ déploiement) et que la dérive soit détectée.

## Facteurs de décision

- Traçabilité et revue de chaque changement.
- Absence de clés AWS longue durée.
- Reproductibilité.

## Options considérées

1. GitOps : plan en PR, apply par la CI uniquement ; seul `infra/bootstrap` est appliqué localement par un humain.
2. Applies locaux par les membres de l'équipe.

## Décision

Option 1. La CI s'authentifie via OIDC GitHub : rôle de plan en lecture seule (`sub` = `repo:<org>/<repo>:pull_request`), rôle d'apply par environnement (`sub` = `repo:<org>/<repo>:environment:<env>`), approbation manuelle pour prod. Le bootstrap (bucket d'état, KMS, rôles OIDC) est la seule exception, car il crée les prérequis de la CI. Aucune modification en console.

## Conséquences

- Positives : historique complet, revue obligatoire, détection de dérive possible par plan planifié.
- Négatives : boucle de retour plus lente pour l'infrastructure ; le bootstrap reste un point manuel à documenter.

## Impact sécurité

Pas d'identifiants longue durée ; le rôle d'apply ne peut créer que des rôles portant la permissions boundary. Contrôles (Checkov, Trivy, tflint, gitleaks, zizmor, actionlint) exécutés avant tout apply.

## Impact coût

Minutes CI uniquement ; pas d'outil GitOps supplémentaire.

## Liens

- NFR-01
- ADR [0001](0001-opentofu.md)
- `.kiro/steering/security.md`

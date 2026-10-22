# 0001 — OpenTofu comme outil d'infrastructure as code

- Statut : Accepté
- Date : 2026-10-22
- Décideurs : AS, OPS

## Contexte

Toute l'infrastructure doit être décrite en code (règle « everything as code »), revue en PR et appliquée par la CI. Il faut un outil déclaratif, testable et dont l'état peut être protégé.

## Facteurs de décision

- Licence ouverte et gouvernance communautaire.
- Chiffrement natif de l'état et du plan.
- Tests de modules intégrés (`tofu test`, `mock_provider`).
- Écosystème de qualité (tflint, Checkov, Trivy, terraform-docs).

## Options considérées

1. OpenTofu.
2. Terraform (licence BUSL).
3. AWS CloudFormation / CDK.

## Décision

OpenTofu (≥ 1.10, version épinglée dans `.mise.toml`, fournisseur AWS épinglé sur la majeure, fichier de verrouillage multi-plateforme commis). Il offre le chiffrement client de l'état et du plan (bloc `encryption`, fournisseur `aws_kms`, `enforced = true`), que Terraform ne propose pas, et reste compatible avec l'outillage HCL existant. CloudFormation/CDK lient l'équipe à un seul fournisseur et n'apportent pas de tests unitaires avec mocks aussi simples.

## Conséquences

- Positives : état chiffré de bout en bout, tests unitaires sans compte AWS, modules réutilisables.
- Négatives : le binaire est `tofu`, jamais `terraform` ; certaines documentations tierces ciblent Terraform.

## Impact sécurité

L'état peut contenir des données sensibles : backend S3 avec `use_lockfile`, SSE-KMS, plus chiffrement client OpenTofu. Les fichiers `*.tfstate` ne sont jamais lus ni copiés hors du backend.

## Impact coût

Outil gratuit. Coût marginal du bucket d'état et de la clé KMS.

## Liens

- `.kiro/steering/iac.md`, `.kiro/steering/security.md`
- ADR [0009](0009-gitops-no-local-apply.md)
- EN-91

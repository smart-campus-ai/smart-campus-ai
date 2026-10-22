# Runbook — bootstrap du compte (state OpenTofu, puis identité CI)

Seul apply local autorisé (ADR 0009). Exécuté par l'OPS, avec le profil temporaire du workshop. Les identifiants ne sont jamais copiés dans le dépôt ni dans GitHub.

- Compte : 762233769579 — rôle `WSParticipantRole` — région **us-east-1** (ADR 0013).
- Code : `infra/bootstrap` (modules `state-backend` [EN-12] et `github-oidc` [EN-13]).

## 0. Prérequis

```bash
export AWS_PROFILE=smartcampus-ws AWS_REGION=us-east-1
aws sts get-caller-identity --query Arn --output text   # doit afficher .../WSParticipantRole/...
git switch develop && git pull
```

## 1. State backend (EN-12) — applicable avec `WSParticipantRole`

```bash
mise exec -- tofu -chdir=infra/bootstrap init -input=false
mise exec -- tofu -chdir=infra/bootstrap plan -input=false \
  -target=module.state_backend \
  -var 'admin_principal_arns=["arn:aws:iam::762233769579:role/WSParticipantRole"]' \
  -out=bootstrap.tfplan
# relire : 9 ajouts attendus (CMK + alias, bucket sc-tfstate-762233769579 et ses 7 configurations), 0 changement, 0 destruction
mise exec -- tofu -chdir=infra/bootstrap apply bootstrap.tfplan
mise exec -- tofu -chdir=infra/bootstrap output
```

Le state du bootstrap reste local (`infra/bootstrap/terraform.tfstate`, ignoré par git, sans secret) jusqu'à l'étape 3.

## 2. Identité CI (EN-13) — BLOQUÉ (issue #98)

`WSParticipantRole` n'a aucune autorisation `iam:CreateOpenIDConnectProvider` ni `iam:PutRolePermissionsBoundary` (lecture des policies `ws-default-policy` et `console-iam-policy-0`). Options :

1. un rôle du workshop avec ces droits, puis un plan complet relu et appliqué :

   ```bash
   mise exec -- tofu -chdir=infra/bootstrap plan -input=false \
     -var 'admin_principal_arns=["arn:aws:iam::762233769579:role/WSParticipantRole"]' \
     -out=bootstrap-full.tfplan
   # relire : fournisseur OIDC, rôles sc-gha-plan / sc-gha-apply-{dev,prod}, boundaries ; 0 changement sur le state backend
   mise exec -- tofu -chdir=infra/bootstrap apply bootstrap-full.tfplan
   ```

2. fournisseur OIDC pré-créé par les organisateurs :

   ```bash
   mise exec -- tofu -chdir=infra/bootstrap plan -input=false \
     -var 'admin_principal_arns=["arn:aws:iam::762233769579:role/WSParticipantRole"]' \
     -var create_oidc_provider=false \
     -var existing_oidc_provider_arn=arn:aws:iam::762233769579:oidc-provider/token.actions.githubusercontent.com \
     -out=bootstrap-full.tfplan
   mise exec -- tofu -chdir=infra/bootstrap apply bootstrap-full.tfplan
   ```

3. si les boundaries ne peuvent pas être posées : adaptation du module (ADR à venir).

## 3. Migration du state du bootstrap dans le bucket

Invariant state (security.md) : le state migré doit aussi être chiffré côté client. Avant la migration, ajouter le bloc `encryption` décrit dans `infra/bootstrap/backend.tf` (étape 3 du commentaire : `key_provider "aws_kms"` sur `state_kms_key_arn`, `method "aes_gcm"`, `fallback` vers `unencrypted` le temps de la migration, puis `enforced = true` pour le state et le plan).

Décommenter ensuite le bloc `backend "s3"` de `infra/bootstrap/backend.tf` avec les sorties de l'étape 1, puis :

```bash
mise exec -- tofu -chdir=infra/bootstrap init -migrate-state
# vérifier la présence de bootstrap/bootstrap.tfstate dans le bucket, puis supprimer les fichiers de state locaux
```

## 4. Variables GitHub (jamais de secrets)

Sorties → variables **du dépôt** (lues par `iac-plan.yml` sur les PR, sans environnement) et **des environnements** `dev` et `prod` (lues par les apply) ; voir `docs/runbooks/ci-variables.md` :

```bash
gh variable set STATE_BUCKET      --body "<state_bucket_name>"
gh variable set STATE_KMS_KEY_ARN --body "<state_kms_key_arn>"
gh variable set AWS_REGION        --body us-east-1
for env in dev prod; do
  gh variable set STATE_BUCKET      --env $env --body "<state_bucket_name>"
  gh variable set STATE_KMS_KEY_ARN --env $env --body "<state_kms_key_arn>"
  gh variable set AWS_REGION        --env $env --body us-east-1
done
# après l'étape 2 uniquement :
gh variable set AWS_PLAN_ROLE_ARN --body "<plan_role_arn>"
gh variable set AWS_APPLY_ROLE_ARN --env dev  --body "<apply_role_arn_dev>"
gh variable set AWS_APPLY_ROLE_ARN --env prod --body "<apply_role_arn_prod>"
```

## 5. Validation OIDC

Ouvrir une PR qui modifie `infra/` : le job `plan (foundation)` de `iac-plan.yml` doit assumer le rôle plan et commenter la PR.

## Rollback

Le bucket et la clé ont `prevent_destroy` : aucune destruction accidentelle. Pour repartir de zéro, un admin retire `prevent_destroy`, vide le bucket (versions comprises) puis `tofu destroy` ; la clé passe en suppression programmée (30 jours).

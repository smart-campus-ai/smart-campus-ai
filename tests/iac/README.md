# Tests IaC transverses

Ce dossier porte les contrôles qui ne vivent pas dans un module. Les tests d'un module restent dans `infra/modules/<module>/tests/` (unitaires) et `tests-integration/` (intégration). Guide complet : [`docs/qa/iac-unit-tests.md`](../../docs/qa/iac-unit-tests.md).

## Contenu

| Fichier | Rôle |
|---|---|
| `check_policies.py` | Auto-test des politiques Checkov personnalisées (`policies/`) contre leurs fixtures (`policies/tests/`) |

## Politiques Checkov personnalisées

| ID | Règle |
|---|---|
| `CKV_SC_1` | `assume_role_policy` d'un `aws_iam_role` (JSON en ligne) : principaux `Service` uniquement |
| `CKV_SC_2` | Chaque `aws_kms_key` porte le tag `Environment` |
| `CKV_SC_3` | Chaque `aws_iam_role` définit `permissions_boundary` |
| `CKV_SC_4` | Chaque `aws_cloudwatch_log_group` définit `kms_key_id` et une `retention_in_days` finie |
| `CKV_SC_5` | `aws_iam_policy_document` qui accorde `sts:AssumeRole*` : principaux `Service` uniquement |

## Exécution

```sh
# Vérification automatique : chaque fixture pass_* doit réussir, chaque fixture fail_* doit échouer
mise exec -- python3 tests/iac/check_policies.py

# Lecture brute (les fixtures fail_* apparaissent en échec, c'est voulu)
mise exec -- checkov -d policies/tests --external-checks-dir policies --framework terraform --check CKV_SC_1,CKV_SC_2,CKV_SC_3,CKV_SC_4,CKV_SC_5
```

`task check` applique les mêmes politiques à `infra/` (`task sec:iac` ajoute `--external-checks-dir policies`). Les fixtures ne sont pas scannées par `task sec:iac`.

## Ajouter une politique

1. Créer `policies/ckv_sc_<n>_<sujet>.py` (une classe, `check = …()` en bas du fichier) avec l'ID `CKV_SC_<n>`.
2. Créer `policies/tests/ckv_sc_<n>/pass.tf` et `fail.tf` : blocs nommés `pass_*` et `fail_*`, chaque fixture `pass_*` doit aussi réussir les autres politiques `CKV_SC_*`.
3. Commencer chaque fixture par `# tflint-ignore-file: terraform_required_version, terraform_required_providers` (tflint parcourt le dépôt en récursif).
4. Lancer `check_policies.py`, puis compléter le tableau ci-dessus et `docs/qa/iac-unit-tests.md`.

Un skip reste possible avec `# checkov:skip=CKV_SC_<n>: <raison>` dans le bloc, à lister dans la PR.

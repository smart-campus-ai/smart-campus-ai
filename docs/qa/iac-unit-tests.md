# Guide des tests unitaires IaC (EN-82)

Chaque module OpenTofu prouve ses invariants de sécurité à chaque PR, sans compte AWS : `tofu test`, provider simulé, `command = plan`. Ce guide fixe les conventions réutilisées par tous les modules. Stratégie générale : [`test-strategy.md`](test-strategy.md). Matrice : [`traceability.md`](traceability.md). Propriétaire : QE.

Modules de référence : `infra/modules/state-backend/tests/unit.tftest.hcl` (EN-12) et `infra/modules/github-oidc/tests/unit.tftest.hcl` (EN-13).

## 1. Où vivent les tests

| Niveau | Emplacement | Exécution | AWS |
|---|---|---|---|
| Unitaire | `infra/modules/<module>/tests/unit.tftest.hcl` | `task test:unit` (local, CI, `task check`) | non |
| Intégration | `infra/modules/<module>/tests-integration/integration.tftest.hcl` | `task test:integration ENV=dev` (à la demande) | oui, compte dev |
| Politiques Checkov | `policies/` + fixtures `policies/tests/` | `task sec:iac` (partie de `task check`) | non |

`tests-integration/` n'est pas `tests/` : `task test:unit` lance tous les fichiers de `tests/` et doit rester hors ligne. Le `Taskfile` lance l'intégration avec `-test-directory=tests-integration`. C'est un écart assumé avec la mention `tests/integration.tftest.hcl` des règles générales.

## 2. Nommage et traçabilité

- Nom du `run` : `<id>_ac<n>_<comportement>` en minuscules, par exemple `en12_ac2_key_rotation_enabled`, `en13_ac1_plan_trust_pinned_to_pull_request`.
- Commentaire juste au-dessus du `run` : `# EN12-AC2: <phrase qui reprend le critère>`. L'ID en majuscules est celui du backlog (`EN-12-AC2`), le `run` utilise le même ID sans tiret entre lettres et chiffres.
- Une variante d'un même AC garde le préfixe et change le suffixe : `en12_ac2_rejects_deletion_window_below_7`, `en12_ac2_rejects_deletion_window_above_30`.
- Un finding de revue renvoie à son identifiant dans le commentaire : `# EN-13-AC1 (F5): ...`.
- Les `error_message` disent l'invariant violé, pas la valeur : `"The plan role must carry the ci boundary."`.
- Correspondance avec la matrice : un `run` = un test `UNIT-<module>-nnn` de `traceability.md`. Le test ID porte le nom du `run` dans la colonne « Intitulé ». Ajouter ou mettre à jour la ligne dans la même PR.
- Un test vérifie un AC. Un AC sans `run` correspondant est une lacune à ouvrir en issue, pas à ignorer.

## 3. Squelette d'un fichier

```hcl
mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "123456789012" } # ID de documentation
  }
  override_data {
    target = data.aws_partition.current
    values = { partition = "aws" }
  }
  # ... overrides de ressources et de documents de politique (section 4)
}

variables {
  name_prefix = "sc"
}

# EN12-AC1: bucket blocks all public access
run "en12_ac1_bucket_public_access_blocked" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.state.block_public_acls
    error_message = "Block Public Access must be fully enabled on the state bucket."
  }
}
```

Règles :
- Toujours `command = plan`. Les tests unitaires n'appliquent jamais.
- Valeurs fictives uniquement : compte `123456789012`, ARN construits à la main. Jamais d'identifiant réel.
- Un `run` regroupe les `assert` d'un même invariant. Les variations de variables passent par un bloc `variables {}` dans le `run`.
- Déterminisme : aucune horloge, aucun `uuid()`, aucun `timestamp()` dans une assertion.
- Budget : moins de 2 minutes pour l'ensemble des modules. Pas de `run` qui ne teste rien de nouveau.

## 4. Comment simuler

`mock_provider "aws"` fournit des valeurs aléatoires pour les attributs calculés. Deux problèmes en découlent, et deux outils les règlent.

| Besoin | Outil | Exemple |
|---|---|---|
| Attribut calculé utilisé dans une ARN, une politique ou un nom (`arn`, `id`, `key_id`) | `override_resource` avec `values` | l'ARN du fournisseur OIDC, de la clé KMS, du bucket |
| Identité du compte et partition | `override_data` sur `aws_caller_identity.current` et `aws_partition.current` | `account_id = "123456789012"` |
| Attribut `json` d'un `aws_iam_policy_document` | `override_data` avec un JSON valide minimal | `json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"` |

Pourquoi simuler le `json` : le mock renvoie une chaîne aléatoire que `aws_iam_role`, `aws_iam_policy`, `aws_kms_key` et `aws_s3_bucket_policy` rejettent comme JSON invalide. Les invariants ne se lisent donc pas dans le JSON mais dans les **arguments du document**, connus au plan :

```hcl
condition = anytrue([
  for s in data.aws_iam_policy_document.bucket.statement :
  s.sid == "DenyInsecureTransport" && s.effect == "Deny" && anytrue([
    for c in s.condition :
    c.variable == "aws:SecureTransport" && c.test == "Bool" && contains(c.values, "false")
  ])
])
```

Pièges connus :
- Un ARN calculé non surchargé rend les arguments du document inconnus au plan : l'assertion échoue avec « unknown value ». Ajouter l'`override_resource` correspondant.
- `override_resource` ne remplace que les attributs listés : les autres restent aléatoires.
- Un `override_data` est requis pour **chaque** document de politique, y compris ceux en `for_each`.
- Les ressources en `count` ou `for_each` s'adressent par index ou clé : `aws_iam_role.apply["dev"]`.

## 5. Invariants de référence (AC2)

Exemples d'assertions à reprendre. Chacun cible un attribut connu au plan.

BPA du bucket (state-backend) :

```hcl
assert {
  condition = alltrue([
    aws_s3_bucket_public_access_block.state.block_public_acls,
    aws_s3_bucket_public_access_block.state.block_public_policy,
    aws_s3_bucket_public_access_block.state.ignore_public_acls,
    aws_s3_bucket_public_access_block.state.restrict_public_buckets,
  ])
  error_message = "Block Public Access must be fully enabled."
}
```

Rotation KMS :

```hcl
assert {
  condition     = aws_kms_key.this.enable_key_rotation == true
  error_message = "KMS key rotation must be enabled."
}
```

Politique TLS (bucket) : voir `en12_ac1_bucket_policy_denies_insecure_access` (`aws:SecureTransport` = `false` refusé, `s3:TlsVersion` < 1.2 refusé).

Absence d'action wildcard dans les politiques générées :

```hcl
assert {
  condition = alltrue([
    for s in data.aws_iam_policy_document.example.statement :
    !anytrue([for a in s.actions : a == "*" || a == "kms:*"])
  ])
  error_message = "Policies must list explicit actions."
}
```

Un `Resource "*"` n'est admis que pour les actions sans support de niveau ressource : voir `en13_ac4_resource_star_only_allowlisted`, qui garde la liste fermée.

Lambda arm64, rétention des logs, WAF attaché (modèles à reprendre quand les modules existent, noms d'attributs du provider AWS) :

```hcl
# Lambda arm64 + tracing actif
assert {
  condition     = contains(aws_lambda_function.this.architectures, "arm64")
  error_message = "Lambda functions must run on arm64."
}
assert {
  condition     = one(aws_lambda_function.this.tracing_config).mode == "Active"
  error_message = "Active tracing is required."
}

# Journaux : rétention finie et chiffrement KMS
assert {
  condition     = aws_cloudwatch_log_group.this.retention_in_days > 0 && aws_cloudwatch_log_group.this.kms_key_id != null
  error_message = "Log groups need a finite retention and a KMS key."
}

# WAF régional attaché à l'étape de l'API
assert {
  condition     = aws_wafv2_web_acl_association.api.web_acl_arn == aws_wafv2_web_acl.regional.arn
  error_message = "The regional web ACL must be attached to the API stage."
}
```

Les politiques du dépôt (section 8) vérifient une partie de ces règles sur le code source ; les tests unitaires les vérifient sur le plan, y compris pour les valeurs issues de variables.

## 6. Validations de variables (AC3)

Une variable validée a au moins un `run` avec une valeur invalide et `expect_failures`. Un seul défaut par `run`, pour savoir quelle règle échoue.

```hcl
# EN12-AC2: rejects a KMS deletion window below 7 days
run "en12_ac2_rejects_deletion_window_below_7" {
  command = plan

  variables {
    kms_deletion_window_in_days = 6
  }

  expect_failures = [var.kms_deletion_window_in_days]
}
```

Couvrir les bornes de chaque côté, la liste vide, le format (ARN, préfixe) et les dépendances entre variables (ex. journalisation activée sans bucket cible). Le cas valide est déjà couvert par les autres `run`.

## 7. Exécuter

| Commande | Effet |
|---|---|
| `task test:unit` | `tofu init -backend=false` puis `tofu test` dans chaque `infra/modules/*` qui a un dossier `tests/` ; auto-test du script d'attribution |
| `task check` | format, lint, sécurité (dont Checkov et `policies/`), `task test:unit`, vérification des README |
| `tofu -chdir=infra/modules/<module> test -filter=tests/unit.tftest.hcl` | un module, un fichier |
| `tofu -chdir=infra/modules/<module> test -verbose` | détail des plans en cas d'échec |

Prérequis : toolchain épinglée (`task setup`). Aucun identifiant AWS n'est nécessaire ni lu : un test unitaire qui en réclame est un défaut du test. Un test en échec fait échouer `task check` et la CI (AC4).

Un `run` qui échoue à cause d'une valeur inconnue au plan : ajouter l'`override_resource`, pas un contournement dans l'assertion.

## 8. Politiques Checkov personnalisées

Les règles du dépôt qui se lisent sur le code vivent dans `policies/`. `task sec:iac` les applique à `infra/` dès que le dossier existe. Détail et procédure d'ajout : [`tests/iac/README.md`](../../tests/iac/README.md).

| ID | Règle | Origine |
|---|---|---|
| `CKV_SC_1` | `assume_role_policy` en ligne d'un `aws_iam_role` : principaux `Service` uniquement | suivi EN-13 |
| `CKV_SC_5` | `aws_iam_policy_document` avec `sts:AssumeRole*` : principaux `Service` uniquement | suivi EN-13 |
| `CKV_SC_2` | `aws_kms_key` avec le tag `Environment` | suivi EN-13 |
| `CKV_SC_3` | `aws_iam_role` avec `permissions_boundary` | règle de sécurité |
| `CKV_SC_4` | `aws_cloudwatch_log_group` avec `kms_key_id` et rétention finie | règle de sécurité |

Le module `github-oidc` est exclu de `CKV_SC_1` et `CKV_SC_5` : sa confiance repose sur un principal `Federated` épinglé par `sub` et `aud`.

Limites à connaître :
- Les `default_tags` du provider ne sont pas visibles pour Checkov. `CKV_SC_2` échoue quand `tags` est absent ou entièrement connu sans `Environment`. Il ne rapporte rien quand `tags` dépend d'une variable non résolue (`merge(var.tags, ...)`). Le test unitaire du module ou de la pile doit alors vérifier le tag.
- Une `assume_role_policy` qui référence `data.aws_iam_policy_document.x.json` n'est pas lisible au niveau de la ressource : `CKV_SC_5` couvre le document.

Fixtures : `policies/tests/ckv_sc_<n>/{pass,fail}.tf`. Les blocs `pass_*` doivent réussir, les blocs `fail_*` doivent échouer. Vérification automatique :

```sh
mise exec -- python3 tests/iac/check_policies.py
```

Lecture brute, où les `fail_*` apparaissent en échec par construction :

```sh
mise exec -- checkov -d policies/tests --external-checks-dir policies --framework terraform --check CKV_SC_1,CKV_SC_2,CKV_SC_3,CKV_SC_4,CKV_SC_5
```

## 9. Tests d'intégration (AC5)

Dossier `infra/modules/<module>/tests-integration/`, lancé par `task test:integration ENV=dev` : `tofu test` applique le module dans le compte dev, vérifie, puis détruit. Réservé à ce que le provider simulé ne prouve pas.

| Couvre | Ne couvre pas |
|---|---|
| Existence réelle des ressources et des noms (`apply_role_arns`, `workload_boundary_arns`) | Ce qui se prouve au plan : tout reste en unitaire |
| Refus IAM réels (voir ci-dessous) | Comportement applicatif : tests `SMK`, `SEC`, `E2E` |
| Chaînage de ressources que le mock masque (dépendances, ordre) | Charge, WAF en débit : tests post-déploiement |

Cas prioritaire (suivi EN-13) : `iam:CreateRole` **sans** permissions boundary doit être refusé par le rôle d'apply. Trois étapes, dans `github-oidc/tests-integration/` :
1. rôle `scit-dev-probe` sans boundary : `AccessDenied` attendu ;
2. même rôle avec la boundary de prod : `AccessDenied` attendu ;
3. même rôle avec la boundary de dev : succès, puis nettoyage.

L'étape réelle exige une session qui assume le rôle d'apply (alias de provider avec `assume_role`) et une assertion sur le diagnostic. Le squelette actuel documente le scénario et vérifie les noms ; il reste à écrire.

Règles :
- Variables d'entrée par `TF_VAR_*` (jamais dans le dépôt) ; un préfixe jetable (`scit`) isole les ressources ;
- Les ressources avec `prevent_destroy` (boundaries) bloquent le nettoyage : supprimer à la main les restes ou utiliser un compte bac à sable ;
- Exécution manuelle ou nocturne sur dev (étape S4), jamais dans `task check`.

## 10. Liste de contrôle d'un module

- [ ] `tests/unit.tftest.hcl` avec `mock_provider "aws"` et `command = plan` partout.
- [ ] Au moins un `run` par invariant de sécurité dont le module est responsable (section 5).
- [ ] Un `run` `expect_failures` par variable validée (section 6).
- [ ] Noms `<id>_ac<n>_<comportement>` et commentaire `# <ID>-AC<n>:` (section 2).
- [ ] `traceability.md` mis à jour (ligne `UNIT-<module>-nnn`).
- [ ] `task check` vert sans identifiants AWS.
- [ ] Si un refus IAM réel compte : squelette dans `tests-integration/`.

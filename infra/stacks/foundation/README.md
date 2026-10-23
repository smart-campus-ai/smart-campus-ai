# Stack foundation

Clés KMS de domaine (`data`, `logs`, `ai`, module `kms-keys`), clé et topic SNS d'alertes ops, budget optionnel et paramètres SSM `/smartcampus/<env>/foundation/*` consommés par la stack `platform`.

## Tests

Cette stack n'a pas de tests unitaires : `task test:unit` ne couvre que les modules (`infra/modules/<name>/tests`). Les invariants de sécurité sont portés par les modules (`kms-keys`, `budget`) et testés là.

Pour la stack elle-même, les contrôles sont :

- les validations de variables et les `precondition` / `postcondition` (comptes des ARN, ARN du topic d'alertes), évaluées par `tofu validate` et par le plan ;
- `task check` (fmt, validate, tflint, Checkov, Trivy) ;
- le plan relu en PR (`iac-plan`), puis l'apply par la CI.

## Second apply

Les ARN de la distribution CloudFront et des rôles GuardDuty n'existent qu'après la stack `platform` : voir `docs/runbooks/foundation-second-apply.md`.

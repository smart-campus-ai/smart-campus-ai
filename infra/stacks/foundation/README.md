# Stack foundation

Clés KMS de domaine (`data`, `logs`, `ai`, `edge`, module `kms-keys`), clé et topic SNS d'alertes ops, budget optionnel et paramètres SSM `/smartcampus/<env>/foundation/*` consommés par la stack `platform`.

## Tests

Cette stack n'a pas de tests unitaires : `task test:unit` ne couvre que les modules (`infra/modules/<name>/tests`). Les invariants de sécurité sont portés par les modules (`kms-keys`, `budget`) et testés là.

Pour la stack elle-même, les contrôles sont :

- les validations de variables et les `precondition` / `postcondition` (comptes des ARN, ARN du topic d'alertes), évaluées par `tofu validate` et par le plan ;
- `task check` (fmt, validate, tflint, Checkov, Trivy) ;
- le plan relu en PR (`iac-plan`), puis l'apply par la CI.

## Second apply

L'ARN du rôle GuardDuty Malware Protection n'existe qu'après la stack `platform` : voir `docs/runbooks/foundation-second-apply.md`. CloudFront n'en a plus besoin : la clé `edge` porte une déclaration limitée aux distributions du compte.

## Rôle CloudWatch d'API Gateway

`apigateway_account.tf` crée le rôle (confiance `apigateway.amazonaws.com`, `aws:SourceAccount`, politique gérée `AmazonAPIGatewayPushToCloudWatchLogs`, sans permissions boundary : ADR-0014 option B) et l'enregistre dans `aws_api_gateway_account`. Ce paramètre est unique par compte et par région : `manage_api_gateway_account` vaut `true` en dev et `false` en prod (même compte pendant l'atelier, ADR-0002).

# Second apply de la stack foundation

La clé KMS `data` de la stack `foundation` ouvre deux accès dont les producteurs sont créés par la stack `platform` : la distribution CloudFront (déchiffrement des objets SSE-KMS via l'OAC) et les rôles GuardDuty Malware Protection for S3 (analyse et tag des objets). Au premier apply de `foundation`, ces listes sont vides et les deux accès sont désactivés. Il faut donc réappliquer `foundation` une fois `platform` créée.

## Quand

- Après le premier apply réussi de `platform` (distribution et rôles de scan créés), pour chaque environnement (`dev`, `prod`).
- Chaque fois que la distribution ou un rôle de scan est recréé : son ARN change et l'ancien accès ne couvre plus le nouveau.

Tant que ce second apply n'est pas fait, CloudFront ne peut pas lire les pièces jointes ou la SPA chiffrées avec la clé `data` et les objets ne sont pas analysés par GuardDuty.

## Règles

- Jamais d'apply local : l'apply passe par le workflow d'apply de la CI (`iac-apply`, EN-73), dans l'environnement GitHub de l'environnement visé (`prod` demande une approbation et la branche `main`).
- Les ARN contiennent l'ID du compte : ils ne sont pas écrits dans `infra/envs/<env>/foundation.tfvars`. Ils sont fournis par des variables d'environnement GitHub (non secrètes) exposées au job sous la forme `TF_VAR_<nom>`.
- Aucun joker (`*`, `?`). Chaque ARN doit appartenir au compte (validation de variable, puis `precondition` au plan).

## Procédure

1. Relever les valeurs dans les sorties de `platform` ou dans les paramètres SSM publiés sous `/smartcampus/<env>/platform/` (lecture seule, avec un profil de lecture, jamais avec le rôle d'apply) :

   ```bash
   tofu -chdir=infra/stacks/platform output
   aws ssm get-parameters-by-path --path "/smartcampus/<env>/platform/" --recursive --query "Parameters[].Name"
   ```

   Repérer l'ARN de la distribution (`arn:aws:cloudfront::<account-id>:distribution/<id>`) et les ARN des rôles de scan (`arn:aws:iam::<account-id>:role/<scan-role>`). Les noms exacts des sorties et des paramètres sont ceux de la stack `platform` ; les confirmer à la relecture de sa PR.

2. Les enregistrer dans l'environnement GitHub visé (Settings → Environments → `<env>` → Variables) :

   | Variable | Valeur |
   |---|---|
   | `TF_VAR_cloudfront_distribution_arns` | `["arn:aws:cloudfront::<account-id>:distribution/<id>"]` |
   | `TF_VAR_guardduty_malware_protection_role_arns` | `["arn:aws:iam::<account-id>:role/<scan-role>"]` |

   Le workflow d'apply doit transmettre ces variables au job sous ces noms. Tant qu'`iac-apply` (EN-73) n'existe pas, ce second apply est bloqué : ne pas le contourner par un apply local.

3. Lancer le workflow `iac-apply` pour la stack `foundation` de l'environnement visé (`dev` depuis `develop`, `prod` depuis `main` avec approbation manuelle). Relire le plan affiché par le job avant d'approuver : il doit montrer uniquement la mise à jour de la politique de la clé `data` (`module.kms_keys.aws_kms_key.this["data"]`). Toute autre modification est anormale : s'arrêter et investiguer.

4. Laisser le job appliquer avec les `TF_VAR_*` de l'environnement. Le déclencheur exact (dispatch manuel ou push) est défini par `iac-apply` (EN-73) ; mettre ce runbook à jour avec la commande exacte quand le workflow existe.

5. Vérifier après l'apply, en lecture seule :

   ```bash
   aws kms get-key-policy --key-id alias/sc-<env>-data --policy-name default --query Policy --output text
   ```

   La politique contient les déclarations de la distribution (`aws:SourceArn`) et des rôles de scan, sans joker. Ne pas coller la politique dans une issue ou une PR : elle contient l'ID du compte.

## Retour arrière

Vider les deux variables d'environnement GitHub (`[]`) et relancer l'apply : les deux accès sont retirés. La clé n'est pas touchée, seule sa politique change.

## Si le plan échoue

- Validation `cloudfront_distribution_arns` ou `guardduty_malware_protection_role_arns` : l'ARN est mal formé ou contient un joker.
- `precondition` sur `aws_kms_key.alerts` : un ARN appartient à un autre compte. Corriger la variable, ne pas assouplir la règle.

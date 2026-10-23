# Second apply de la stack foundation

La clé KMS `data` de la stack `foundation` ouvre un accès dont le producteur est créé par la stack `platform` : les rôles GuardDuty Malware Protection for S3 (analyse et tag des objets). Au premier apply de `foundation`, la liste des rôles est vide et l'accès est désactivé. Il faut donc réappliquer `foundation` une fois `platform` créée, **seulement si `enable_malware_protection` est `true`** (prod ; `false` en dev pendant l'atelier, EN-11). Sinon, ce runbook ne s'applique pas.

CloudFront n'est plus concerné : la clé `edge` de `foundation` (bucket de la SPA) porte une déclaration limitée aux distributions du compte (`aws:SourceArn` en `ArnLike` sur `arn:<partition>:cloudfront::<compte>:distribution/*`), créée dès le premier apply. L'ARN de la distribution n'est plus nécessaire.

## Quand

- Après le premier apply réussi de `platform` avec `enable_malware_protection = true` (rôle de scan créé), pour chaque environnement concerné.
- Chaque fois que le rôle de scan est recréé : son ARN change et l'ancien accès ne couvre plus le nouveau.

Tant que ce second apply n'est pas fait, les objets des pièces jointes ne sont pas analysés par GuardDuty.

## Règles

- Jamais d'apply local : l'apply passe par le workflow d'apply de la CI (`iac-apply`, EN-73), dans l'environnement GitHub de l'environnement visé (`prod` demande une approbation et la branche `main`).
- L'ARN contient l'ID du compte : il n'est pas écrit dans `infra/envs/<env>/foundation.tfvars`. Il est fourni par une variable d'environnement GitHub (non secrète) exposée au job sous la forme `TF_VAR_<nom>`.
- Aucun joker (`*`, `?`). L'ARN doit appartenir au compte (validation de variable, puis `precondition` au plan).

## Procédure

1. Relever la valeur dans la sortie de `platform` ou dans le paramètre SSM publié sous `/smartcampus/<env>/platform/` (lecture seule, avec un profil de lecture, jamais avec le rôle d'apply) :

   ```bash
   tofu -chdir=infra/stacks/platform output attachments_malware_role_arn
   aws ssm get-parameter --name "/smartcampus/<env>/platform/attachments/malware-role-arn" --query "Parameter.Value" --output text
   ```

   | Valeur | Sortie `platform` | Paramètre SSM (`/smartcampus/<env>/platform/…`) |
   |---|---|---|
   | ARN du rôle de scan (`arn:aws:iam::<account-id>:role/<scan-role>`) | `attachments_malware_role_arn` | `attachments/malware-role-arn` |

2. L'enregistrer dans l'environnement GitHub visé (Settings → Environments → `<env>` → Variables) :

   | Variable | Valeur |
   |---|---|
   | `TF_VAR_guardduty_malware_protection_role_arns` | `["arn:aws:iam::<account-id>:role/<scan-role>"]` |

   Le workflow d'apply doit transmettre cette variable au job sous ce nom. Tant qu'`iac-apply` (EN-73) n'existe pas, ce second apply est bloqué : ne pas le contourner par un apply local.

3. Lancer le workflow `iac-apply` pour la stack `foundation` de l'environnement visé (`dev` depuis `develop`, `prod` depuis `main` avec approbation manuelle). Relire le plan affiché par le job avant d'approuver : il doit montrer uniquement la mise à jour de la politique de la clé `data` (`module.kms_keys.aws_kms_key.this["data"]`). Toute autre modification est anormale : s'arrêter et investiguer.

4. Laisser le job appliquer avec les `TF_VAR_*` de l'environnement. Le déclencheur exact (dispatch manuel ou push) est défini par `iac-apply` (EN-73) ; mettre ce runbook à jour avec la commande exacte quand le workflow existe.

5. Vérifier après l'apply, en lecture seule :

   ```bash
   aws kms get-key-policy --key-id alias/sc-<env>-data --policy-name default --query Policy --output text
   ```

   La politique contient la déclaration du rôle de scan, sans joker. Ne pas coller la politique dans une issue ou une PR : elle contient l'ID du compte.

## Retour arrière

Vider la variable d'environnement GitHub (`[]`) et relancer l'apply : l'accès est retiré. La clé n'est pas touchée, seule sa politique change.

## Si le plan échoue

- Validation `guardduty_malware_protection_role_arns` : l'ARN est mal formé ou contient un joker.
- `precondition` sur `aws_kms_key.alerts` : un ARN appartient à un autre compte. Corriger la variable, ne pas assouplir la règle.

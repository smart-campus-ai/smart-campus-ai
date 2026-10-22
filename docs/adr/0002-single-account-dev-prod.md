# 0002 — Dev et prod dans un compte unique pendant l'atelier

- Statut : Accepté
- Date : 2026-10-22
- Décideurs : AS, OPS

## Contexte

L'atelier ne dispose que d'un compte AWS. Les bonnes pratiques recommandent un compte par environnement pour isoler les rayons d'impact.

## Facteurs de décision

- Contrainte : un seul compte disponible.
- Isolation suffisante entre dev et prod pour la démonstration.
- Passage ultérieur en multi-comptes sans réécriture.

## Options considérées

1. Dev et prod dans le même compte, isolés par préfixe et clé d'état.
2. Un compte par environnement (AWS Organizations).
3. Un seul environnement.

## Décision

Option 1. Préfixes `sc-dev` / `sc-prod`, un état par environnement et par stack (`<env>/<stack>.tfstate`), un fichier `backend.hcl` et des tfvars par environnement, rôles OIDC distincts par environnement GitHub. Le code reste « multi-account ready » : passer à l'option 2 se limite à changer `backend.hcl` et les tfvars.

## Conséquences

- Positives : démarrage immédiat, un seul socle de sécurité à gérer.
- Négatives : quotas et services de niveau compte (CloudTrail, GuardDuty, Security Hub, Config) partagés ; une erreur IAM peut toucher les deux environnements.

## Impact sécurité

L'isolation repose sur les préfixes dans les ARN des politiques IAM et la permissions boundary. Le service de base de sécurité est activé par des bascules pour ne pas dupliquer les services de niveau compte.

## Impact coût

Pas de coût d'organisation supplémentaire ; services de niveau compte payés une seule fois.

## Liens

- `AGENTS.md` (Environnements), `.kiro/steering/architecture.md` (Cross-cutting)
- EN-91

# 0006 — Fonctions Lambda hors VPC

- Statut : Accepté
- Date : 2026-10-22
- Décideurs : AS, OPS

## Contexte

Les fonctions n'accèdent qu'à des API AWS régionales (DynamoDB, S3, Bedrock, SES, SNS, EventBridge Scheduler, SSM). Aucune ressource privée en réseau (base relationnelle, cache) n'est prévue.

## Facteurs de décision

- Gain de sécurité réel d'un VPC dans ce contexte.
- Coût fixe et complexité.
- Latence de démarrage.

## Options considérées

1. Pas de VPC : appels aux API AWS en TLS avec authentification IAM.
2. Lambda dans un VPC avec NAT Gateway.
3. Lambda dans un VPC avec VPC endpoints pour chaque service.

## Décision

Option 1. Toutes les dépendances sont des API AWS régionales joignables en TLS et autorisées par IAM (un rôle par fonction, moindre privilège). Un VPC ajouterait le coût de NAT ou d'endpoints et des démarrages à froid, sans gain de sécurité.

## Conséquences

- Positives : infrastructure plus simple, pas de coût réseau fixe.
- Négatives : toute future dépendance réseau privée imposera un nouvel ADR.

## Impact sécurité

Le contrôle repose sur IAM (politiques scopées, permissions boundary, conditions), TLS et le chiffrement KMS, pas sur l'isolation réseau.

## Impact coût

Aucun NAT Gateway ni endpoint d'interface facturé à l'heure.

## Liens

- `.kiro/steering/architecture.md` (Compute)
- EN-91

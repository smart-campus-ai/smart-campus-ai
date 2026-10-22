# 0005 — Authorizer Cognito User Pool natif

- Statut : Accepté
- Date : 2026-10-22
- Décideurs : AS, OPS, SE

## Contexte

EN-32 demandait initialement un Lambda authorizer pour valider les tokens. Les utilisateurs s'authentifient via Cognito (fédération Entra ID optionnelle) ; les tokens sont donc émis par Cognito.

## Facteurs de décision

- Surface d'attaque et quantité de code de sécurité à maintenir.
- Latence (démarrages à froid).
- Couverture des utilisateurs fédérés.

## Options considérées

1. Authorizer Cognito User Pool natif de l'API REST.
2. Lambda authorizer personnalisé validant le JWT.

## Décision

Option 1. L'authorizer natif valide signature, expiration, émetteur et audience. Les tokens émis par Cognito couvrent aussi les utilisateurs Entra fédérés. Requête sans token ou avec token invalide : 401. Les méthodes admin vérifient en plus `cognito:groups` dans le handler. L'identité d'un étudiant vient toujours du `sub` du JWT, jamais de la requête (OWASP API1/BOLA).

## Conséquences

- Positives : aucun code de validation, pas de démarrage à froid, pas de rôle IAM supplémentaire.
- Négatives : autorisation fine (groupes, propriété) reste à la charge des handlers et doit être testée.

## Impact sécurité

Suppression d'un composant critique écrit à la main ; la validation cryptographique est déléguée au service managé.

## Impact coût

Pas de facturation Lambda pour l'autorisation.

## Liens

- EN-32
- ADR [0004](0004-rest-api-regional-waf.md)

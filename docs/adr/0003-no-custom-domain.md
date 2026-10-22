# 0003 — Pas de nom de domaine personnalisé

- Statut : Accepté
- Date : 2026-10-22
- Décideurs : AS, OPS

## Contexte

Aucun nom de domaine n'est disponible pour l'atelier (décision du 22/10). EN-22 (domaine + ACM) passe au statut « won't ».

## Facteurs de décision

- Disponibilité d'un domaine : nulle.
- HTTPS obligatoire pour l'utilisateur.
- Possibilité d'ajouter un domaine plus tard sans refonte.

## Options considérées

1. URL `*.cloudfront.net` ; code du domaine conservé derrière `enable_custom_domain = false`.
2. Acheter un domaine et créer une zone Route 53.
3. Supprimer tout le code lié au domaine.

## Décision

Option 1. CloudFront est le point d'entrée unique, servi sur `*.cloudfront.net` avec redirection HTTPS et TLSv1.2_2021 minimum. Le code ACM (us-east-1) et alias CloudFront reste dans le module, désactivé. Aucune zone Route 53.

## Conséquences

- Positives : aucun délai d'achat ni de validation DNS.
- Négatives : URL peu lisible ; l'URL `execute-api` de l'API ne peut pas être désactivée, l'API doit donc se protéger seule (voir ADR 0004). Les liens des notifications utilisent l'URL CloudFront.

## Impact sécurité

Le contournement de CloudFront par l'URL `execute-api` est couvert par le WAF régional, la validation de requête et le throttling de l'API REST (RF04).

## Impact coût

Pas de domaine ni de zone hébergée.

## Liens

- EN-22, EN-21, RF04
- ADR [0004](0004-rest-api-regional-waf.md)

# 0004 — API Gateway REST avec WAF régional plutôt qu'API HTTP

- Statut : Accepté
- Date : 2026-10-22
- Décideurs : AS, OPS

## Contexte

Sans domaine (ADR 0003), l'URL `execute-api` reste joignable directement. RF04 exige un WAF et une limitation de débit qui s'appliquent quelle que soit l'URL utilisée.

## Facteurs de décision

- Protection de l'API indépendante de CloudFront.
- Limitation de débit par utilisateur et par IP.
- Validation des entrées au plus tôt.
- Coût à l'échelle du campus.

## Options considérées

1. API Gateway REST (régionale) + web ACL WAF régionale sur le stage.
2. API Gateway HTTP API derrière CloudFront seulement.
3. Lambda function URLs derrière CloudFront.

## Décision

Option 1. Seules les API REST acceptent une web ACL WAF régionale, la validation par modèles JSON Schema, le throttling par stage/méthode et les plans d'usage. Deux web ACL : CLOUDFRONT (us-east-1) sur la distribution, REGIONAL sur le stage. Les deux portent les groupes gérés AWS (Common, KnownBadInputs, IpReputation, AnonymousIp) et une limite de taille du corps ; la régionale porte les règles de débit agrégées sur l'en-tête `Authorization` et par IP. Comportement CloudFront `/api/*` vers l'API (cache désactivé, `Authorization` transmis) : même origine, pas de CORS.

## Conséquences

- Positives : RF04 respecté même en appel direct ; entrées invalides rejetées avant Lambda.
- Négatives : deux web ACL à maintenir ; API REST plus verbeuse à décrire que l'API HTTP.

## Impact sécurité

Défense en profondeur sur les deux points d'entrée ; journaux WAF dans `aws-waf-logs-*`, chiffrés KMS, alarmes sur les blocages.

## Impact coût

Surcoût par million de requêtes de l'API REST négligeable à l'échelle du campus ; coût fixe de deux web ACL et de leurs règles.

## Liens

- RF04, EN-21, EN-22
- ADR [0003](0003-no-custom-domain.md), [0005](0005-native-cognito-authorizer.md)

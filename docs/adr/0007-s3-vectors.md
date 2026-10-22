# 0007 — S3 Vectors comme magasin vectoriel de la Knowledge Base

- Statut : Accepté
- Date : 2026-10-22
- Décideurs : AS, OPS

## Contexte

L'assistant RAG (US07, US10, RF03) s'appuie sur une Bedrock Knowledge Base qui nécessite un magasin vectoriel.

## Facteurs de décision

- Coût plancher à faible volume.
- Délai de provisionnement compatible avec l'atelier.
- Service managé, chiffrement CMK.

## Options considérées

1. S3 Vectors.
2. OpenSearch Serverless.

## Décision

Option 1. OpenSearch Serverless est écarté pour son coût plancher et son temps de provisionnement. Si S3 Vectors ou la Knowledge Base n'est pas disponible dans la région, la solution de repli fera l'objet d'un ADR dédié. Ingestion : bucket de documents source → événement S3 → `kb-sync` → `StartIngestionJob`, statut journalisé.

## Conséquences

- Positives : coût proportionnel à l'usage, pas de cluster à gérer.
- Négatives : dépendance à la disponibilité régionale du service.

## Impact sécurité

Données chiffrées avec la CMK `ai` ; bucket privé avec Block Public Access et politique TLS-only. Le Guardrail (PII, attaques de prompt, ancrage contextuel) reste la protection côté réponse.

## Impact coût

Pas de coût fixe de capacité ; stockage et requêtes facturés à l'usage.

## Liens

- US07, US10, RF03
- `.kiro/steering/architecture.md` (AI assistant)

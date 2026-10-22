# 0008 — Escalade SLA par planification unique par ticket

- Statut : Accepté
- Date : 2026-10-22
- Décideurs : AS, SE

## Contexte

RF01 : un ticket resté « Ouvert » 24 h doit être escaladé.

## Facteurs de décision

- Précision du déclenchement.
- Pas de `Scan` DynamoDB.
- Coût et idempotence.

## Options considérées

1. Une planification EventBridge Scheduler unique par ticket.
2. Règle horaire qui parcourt les tickets ouverts.
3. TTL DynamoDB + stream.

## Décision

Option 1. À la création, `tickets` crée une planification `at(created+24h)` avec `ActionAfterCompletion=DELETE` ciblant `escalation`. `escalation` est idempotente : aucun effet si le ticket n'est plus « Ouvert ». L'option 2 impose un parcours périodique (interdit : jamais de `Scan`) et une précision d'une heure ; l'option 3 n'est pas couverte par l'architecture de référence.

## Conséquences

- Positives : déclenchement à l'heure prévue, aucune lecture inutile, planifications auto-supprimées.
- Négatives : une planification par ticket à créer ; échec de création à gérer côté `tickets`.

## Impact sécurité

Rôle d'exécution du scheduler limité à l'invocation de l'alias `live` de `escalation`, avec conditions `aws:SourceAccount`/`aws:SourceArn`. Échecs asynchrones vers une DLQ SQS.

## Impact coût

Facturation à l'invocation, négligeable au volume du campus ; aucune lecture DynamoDB périodique.

## Liens

- RF01
- `.kiro/steering/architecture.md` (Events and SLA)

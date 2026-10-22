## Contexte

Exigence transverse portée par l'epic E7 : aucune modification manuelle de l'infrastructure AWS. Git est la seule source de vérité ; seul `infra/bootstrap` est appliqué localement, par un humain. Chaque déploiement doit être relié à une issue et à une PR.

## User story

En tant qu'équipe OPS, je veux centraliser et automatiser les déploiements via GitOps, afin d'interdire les modifications manuelles sur l'infrastructure AWS et de tracer chaque changement.

## Critères d'acceptation

```gherkin
# language: fr
Fonctionnalité: NFR-01 — GitOps et traçabilité

  Scénario: AC1 — Aucun apply hors CI sauf bootstrap
    Étant donné les rôles IAM du compte
    Quand on inventorie les principaux autorisés à appliquer les stacks foundation et platform
    Alors seul le rôle apply OIDC lié à un environnement GitHub le peut
    Et "infra/bootstrap" est le seul répertoire appliqué localement

  Scénario: AC2 — Toute modification passe par le pipeline
    Étant donné une modification d'infrastructure fusionnée sur "develop" ou "main"
    Quand le pipeline s'exécute
    Alors le plan revu sur la PR est le plan appliqué

  Scénario: AC3 — Détection de dérive
    Étant donné une ressource modifiée hors OpenTofu
    Quand la détection de dérive s'exécute
    Alors la dérive est signalée par une issue labellisée "drift"

  Scénario: AC4 — Traçabilité issue ↔ PR ↔ déploiement
    Étant donné un déploiement en dev ou en prod
    Quand on consulte son exécution
    Alors on retrouve le commit, la PR (titre conventionnel, "Closes #n") et l'issue liée
```

## Exigences non fonctionnelles

- Aucune clé d'accès longue durée ; OIDC uniquement.
- Les journaux de déploiement ne contiennent ni secret ni contenu du state.

## Notes techniques / décisions

- Exigence vérifiée par la combinaison de EN-13, EN-71, EN-72, EN-73 et EN-75.
- AC3 dépend de EN-75, aujourd'hui priorisé `could` : à aligner (voir questions PO dans le plan de migration).

## Dépendances

- EN-13 — Rôles OIDC
- EN-72 — Plan sur les PR
- EN-73 — Apply GitOps
- EN-75 — Détection de dérive

## Definition of Done

- [ ] Chaque AC vérifié par un contrôle automatisé ou une preuve liée dans l'issue (`NFR-01-AC1 …`)
- [ ] `task check` vert en local et en CI
- [ ] ADR GitOps référencé (EN-91)
- [ ] Issue mise à jour avec une note d'avancement

Migré depuis Pawpawzz/smart-campus-ai#11

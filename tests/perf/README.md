# EN-84 — Tests de performance k6

Vérifie l'exigence de temps de réponse **p95 < 2000 ms** sur les parcours
principaux, avec un échec explicite si un seuil est dépassé (AC4).

## Scénarios (`main.js`)

| Scénario | Endpoint | Seuil p95 |
|---|---|---|
| `create_ticket` | `POST /tickets` | < 2000 ms |
| `list_tickets` | `GET /tickets` | < 2000 ms |
| `kpi` | `GET /kpi` (admin) | < 2000 ms |

Le **chat** est mesuré séparément (latence de génération, seuil à valider par le
PO) et n'est pas inclus ici.

## Profil de charge (AC3)

- **Utilisateurs virtuels (VUS)** : `10` par défaut sur `create_ticket` et
  `list_tickets`, `5` sur `kpi` (moins d'admins). Surchargeable par `VUS`.
- **Durée** : `1m` par défaut (`DURATION`).
- **Hypothèses de charge** : campus ~5 000 étudiants, pic réaliste ~1 % actifs en
  simultané en heure de pointe ⇒ ~50 utilisateurs concurrents tous parcours
  confondus. Le profil par défaut (≈25 VUS cumulés) couvre ce pic avec une marge.
  Ajuster `VUS`/`DURATION` pour un test de capacité plus agressif.
- **Débit WAF / throttling** : les réponses `429` sont **attendues** sous les
  règles de rate-limit (RF04) et le throttling de stage ; elles sont comptées
  comme succès fonctionnel et **exclues** du taux d'erreur métier (AC2). Utiliser
  des utilisateurs de test distincts ou des seuils dev adaptés pour ne pas être
  bloqué par le rate-limit par utilisateur.

## Seuils

- `p(95) < 2000` sur chaque Trend de scénario (AC1).
- `business_errors rate < 0.01` : taux de requêtes en erreur hors `429` attendus
  (AC2).
- k6 sort avec un **code non nul** si un seuil est dépassé, et le résumé indique
  le scénario fautif via sa métrique dédiée (AC4).

## Exécution

Nécessite un environnement déployé (dépend d'EN-74 / #98). Variables d'env :

```sh
export BASE_URL="https://<distribution>.cloudfront.net/api"
export STUDENT_TOKEN="<access token Cognito d'un étudiant de test>"
export ADMIN_TOKEN="<access token Cognito d'un admin de test>"
# Profil optionnel
export VUS=10 DURATION=1m

task perf ENV=dev        # enveloppe `k6 run tests/perf/main.js`
# ou directement :
k6 run tests/perf/main.js
```

Les jetons sont des **secrets** : ne jamais les committer ni les journaliser.
Joindre le résumé d'une exécution dev à l'issue (DoD).

# Démo locale Docker — SmartCampus AI

Lance la plateforme complète **en local, sans AWS** : le frontend (SPA) et le
**vrai code back** (les handlers Lambda `tickets`, `chat`, `kpi`) derrière une
mini-passerelle HTTP, avec des **données de test pré-chargées**.

> Aide de démo uniquement. En production la SPA est servie depuis S3 derrière
> CloudFront et les handlers tournent sur Lambda derrière API Gateway +
> l'authorizer Cognito. La passerelle et les jetons de démo ci-dessous
> n'existent **que** pour la démo locale.

## Lancer

```sh
docker compose -f demo/docker-compose.yml up --build
# puis ouvrir http://localhost:8088
```

Arrêter : `docker compose -f demo/docker-compose.yml down`.

## Se connecter

Sur l'écran de connexion, deux boutons de démo :

- **Entrer en tant qu'étudiant** → identité `student-001` (alice@esiea.fr)
- **Entrer en tant qu'administrateur** → identité `admin-001`

En interne, le bouton émet un jeton `demo.<role>.<sub>` que la passerelle
transforme en claims Cognito (`sub`, `cognito:groups`). Aucun mot de passe,
aucun Cognito.

## Données de test pré-chargées

- **Tickets** (`demo/gateway/demo_seed.py`) : Wi-Fi salle 204 (Ouvert), accès
  salle projet (En cours), compte bloqué (Résolu) pour l'étudiant ; un ticket
  d'un **autre** étudiant (démontre l'isolation BOLA : invisible côté
  `student-001`).
- **Chat** : une session passée (« Horaires de la BU ») avec réponse sourcée.
- **Base de connaissances** : horaires BU, Wi-Fi eduroam, mot de passe,
  restauration. Posez une question couverte → réponse **sourcée** ; une question
  hors base → « Je ne sais pas » + **proposition de ticket pré-rempli** (US10).
- **KPI** : agrégats journaliers sur ~14 jours (volumes, résolus, temps moyen),
  visibles sur le tableau de bord admin.

## Parcours de démo suggérés

1. **Étudiant** : créer un ticket → il apparaît dans « Mes tickets » au statut
   *Ouvert* ; discuter avec l'assistant (poser « horaires de la BU » puis une
   question hors sujet pour voir l'escalade en ticket).
2. **Admin** : ouvrir un ticket, le passer *En cours* avec une note ; consulter
   le tableau de bord **KPI** (réservé admin — un étudiant reçoit 403).

## Architecture de la démo

```
navigateur ──▶ frontend (nginx :8088)
                   │  /            → SPA (build Vite)
                   │  /api/*       → proxy
                   ▼
              gateway (:8080, stdlib Python)
                   └─ invoque les VRAIS handlers services/{tickets,chat,kpi}/app.py
                      avec des stores en mémoire + données de seed
```

- `demo/Dockerfile.frontend` : build pnpm + nginx (`VITE_USE_MOCKS=false`,
  `VITE_DEMO_TOKENS=true`, `VITE_API_BASE_URL=/api`).
- `demo/Dockerfile.gateway` : `python:3.13-slim`, lance `gateway/server.py`.
- `demo/gateway/` : `server.py` (routeur HTTP + chargement isolé des services),
  `demo_wiring.py` (stores en mémoire + câblage), `demo_seed.py` (données).

## Limites assumées

- Stockage **en mémoire** : les données repartent du seed à chaque redémarrage
  du conteneur gateway.
- La passerelle n'implémente pas les pièces jointes S3 (presigned POST) ni les
  notifications SES/SNS — hors périmètre d'une démo locale.
- Les jetons de démo ne sont pas vérifiés cryptographiquement : **ne jamais**
  activer `VITE_DEMO_TOKENS` hors de cette démo.

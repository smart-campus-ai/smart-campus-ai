# SmartCampus AI

Plateforme de gestion des incidents du campus (atelier Capgemini × ESIEA). Les étudiants déclarent et suivent leurs tickets et échangent avec un assistant RAG qui peut transformer une conversation en ticket. Les administrateurs gèrent le cycle de vie des tickets (SLA, notes, affectation) et consultent les KPI.

## Architecture en bref

Serverless, région `eu-west-3` (et `us-east-1` pour le WAF CloudFront).

- **Entrée unique** : CloudFront (URL `*.cloudfront.net`, pas de domaine personnalisé). `/*` → SPA sur S3 privé, `/api/*` → API Gateway REST. WAF sur CloudFront et sur l'API.
- **Identité** : Cognito User Pool (groupes `student`, `admin`), code d'autorisation + PKCE, MFA pour `admin`. Fédération Entra ID en option.
- **Calcul** : une Lambda arm64 par cas d'usage (`tickets`, `kpi`, `chat`, `escalation`, `notifier`, `kb-sync`, `kpi-aggregator`, `pre-token`), sans VPC.
- **Données** : DynamoDB (`tickets`, `chat-sessions`, `kpi`), pièces jointes sur S3 (presigned POST, analyse antimalware), chiffrement KMS partout.
- **SLA** : un planning EventBridge Scheduler à +24 h par ticket déclenche `escalation`.
- **Assistant** : Bedrock Knowledge Base (S3 Vectors) + Guardrail, inférence maintenue en UE.
- **Notifications** : SES (étudiants), SNS (administrateurs / exploitation).

Détail complet et décisions : [`docs/adr/`](docs/adr/) et [`docs/architecture/`](docs/architecture/).

## Prérequis

- Compte GitHub membre de l'organisation, avec 2FA activée.
- Git (version récente).
- [mise](https://mise.jdx.dev) (recommandé) — installe toutes les versions épinglées dans `.mise.toml`.
- Accès AWS : aucun nécessaire pour développer ; les déploiements passent uniquement par la CI (OIDC).

Outils gérés par `.mise.toml` (à installer à la main si vous n'utilisez pas mise) : opentofu, tflint, checkov, trivy, gitleaks, terraform-docs, actionlint, zizmor, lefthook, task, awscli, hurl, k6, node + pnpm, infracost.

## Installation

> `.mise.toml`, `Taskfile.yml` et `lefthook.yml` arrivent avec EN-01 : les commandes `mise` / `task` ci-dessous sont **disponibles après EN-01**.

### macOS

```sh
brew install git mise
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc && exec zsh
git clone https://github.com/smart-campus-ai/smart-campus-ai.git && cd <repo>
git switch develop
mise trust && mise install      # disponible après EN-01
task setup                      # disponible après EN-01 (outils + hooks lefthook)
```

### Linux

```sh
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc && exec bash
git clone https://github.com/smart-campus-ai/smart-campus-ai.git && cd <repo>
git switch develop
mise trust && mise install      # disponible après EN-01
task setup                      # disponible après EN-01
```

### Windows

Utiliser PowerShell 7 (ou WSL 2 et suivre la section Linux).

```powershell
winget install Git.Git jdx.mise
# Ajouter à $PROFILE : (&mise activate pwsh) | Out-String | Invoke-Expression
git clone https://github.com/smart-campus-ai/smart-campus-ai.git; cd <repo>
git config core.autocrlf input
git switch develop
mise trust; mise install        # disponible après EN-01
task setup                      # disponible après EN-01
```

### Sans mise

Installer manuellement chaque outil de la liste ci-dessus **à la version indiquée dans `.mise.toml`**, puis lancer `lefthook install`. Les versions divergentes ne sont pas supportées.

### Variables locales

Copier `.env.example` en `.env` (ignoré par git) et le compléter localement. Ne jamais committer ni partager `.env`.

## Commandes (Taskfile — disponibles après EN-01)

| Commande | Rôle |
|---|---|
| `task setup` | installe la chaîne d'outils épinglée et les hooks git |
| `task check` | fmt + lint + sécurité + tests unitaires (passage obligé avant commit) |
| `task test:unit` | `tofu test` avec mocks |
| `task test:integration ENV=dev` | tests contre le compte dev |
| `task plan ENV=dev STACK=platform` | plan en lecture seule |
| `task docs` | régénère les README des modules |
| `task smoke ENV=dev` / `task perf ENV=dev` | tests smoke (Hurl) / seuils de performance (k6) |

## Workflow git

- `develop` = intégration (branche par défaut, déploie `dev`) ; `main` = production (déploie `prod` après approbation).
- Branche depuis `develop` : `<type>/<issue>-<slug>`, ex. `feat/12-tickets-store`.
- Conventional Commits, PR vers `develop`, 1 approbation + checks verts, squash merge.
- Release : PR `develop` → `main`, tags et `CHANGELOG.md` générés par release-please.
- Aucune modification manuelle dans la console AWS : tout passe par le code et la CI.

Détails : [CONTRIBUTING.md](CONTRIBUTING.md).

## Qui possède quoi

| Domaine | Rôle | Chemins | Responsable |
|---|---|---|---|
| Infra, CI/CD, qualité, architecture | OPS / QE / AS | `infra/`, `.github/`, `tests/`, `policies/`, `docs/` | @PaulPerigault |
| Application | SE | `services/`, `frontend/`, `packages/` | TODO (handles SE) |

Le contrat entre les deux : `packages/contracts` (OpenAPI), variables d'environnement, artefacts Lambda — voir [CONTRIBUTING.md](CONTRIBUTING.md#contrat-infra--app).

## Documentation

- [CONTRIBUTING.md](CONTRIBUTING.md) — règles de contribution, DoD, contrat infra ↔ app
- [docs/onboarding.md](docs/onboarding.md) — checklist d'arrivée d'un membre SE
- [docs/adr/](docs/adr/) — décisions d'architecture
- [docs/architecture/](docs/architecture/), [docs/runbooks/](docs/runbooks/), [docs/qa/](docs/qa/), [docs/backlog/](docs/backlog/)
- [AGENTS.md](AGENTS.md) — carte du dépôt et règles non négociables

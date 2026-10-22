# Kit d'amorçage SmartCampus AI (v2)

À supprimer une fois le dépôt amorcé (Claude Code peut s'en charger dans la PR EN-01).

## Contenu

| Fichier | Lu par | Rôle |
|---|---|---|
| `AGENTS.md` | Claude (via `CLAUDE.md`) et Kiro (natif) | règles communes, source unique |
| `CLAUDE.md` | Claude Code | orchestrateur : délégation à Kiro (`--v3`), protocole `gh` |
| `.claude/settings.json` | Claude Code | permissions (refus de `.env`, d'`apply`, des subagents et du push sur `main`) ; attribution désactivée |
| `.kiro/steering/*.md` | Kiro | architecture v3 et sécurité (toujours chargés) ; IaC, CI/CD, tests (selon les fichiers touchés) ; git (manuel) |
| `.kiro/agents/*.json` | `kiro-cli --v3 --agent` | 7 agents au format V3, modèle fixé par agent |
| `.env.example` | toi | modèle de `.env` (aucune clé AWS) |
| `.gitignore` | git | ignore `.env`, le state OpenTofu, `.idea/`… |
| `docs/backlog/backlog-v2.md` | Claude Code | refonte des 21 issues + nouvelles issues OPS/QE/AS |
| `docs/prompts/00-bootstrap.md` | Claude Code | premier prompt d'orchestration |

## Kiro : V2 par défaut sur 2.33.x

Les agents utilisent le format **V3** (`permissions.rules`). `CLAUDE.md` impose donc `kiro-cli chat --v3 …` à chaque appel. Pour tes propres sessions interactives, lance `kiro-cli --v3`, ou accepte « Switch to V3 » au démarrage.

## Modèles des agents (crédits)

| Agent | Modèle |
|---|---|
| orchestrator, architect, secops | `claude-opus-5.5` (2.0x) |
| iac, cicd, qe | `claude-sonnet-5.5` (1.3x) |
| aws-inspector | `claude-haiku-4.5` (0.4x) |

Si les crédits fondent trop vite, passe `orchestrator` et `architect` en `claude-sonnet-5.5`.

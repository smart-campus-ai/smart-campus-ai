# SmartCampus AI — Agent Guide

Single source of truth for every AI agent working in this repository (Claude Code imports it from `CLAUDE.md`, Kiro loads it natively). Domain details live in `.kiro/steering/*.md` — read the relevant one before touching its area.

## Product

Campus incident platform (Capgemini × ESIEA workshop). Students report and track tickets, chat with a RAG assistant that can escalate to a ticket; admins manage the ticket lifecycle (SLA, notes, assignment) and read KPIs.

## Ownership

| Area | Owner role | Paths |
|---|---|---|
| Infrastructure, CI/CD, quality, architecture | OPS / QE / AS | `infra/`, `.github/`, `tests/`, `policies/`, `docs/` |
| Application | SE | `services/`, `frontend/`, `packages/` |

Agents on the OPS side never implement business logic in `services/` or `frontend/`; they only define the contract (`packages/contracts`, env vars, IAM, deploy pipeline).

## Team

| Handle | Role | Owns (CODEOWNERS) |
|---|---|---|
| @PaulPerigault | OPS | `infra/`, `.github/`, `policies/`, agent and tooling config, everything not listed below; co-owns `docs/adr/`, `docs/architecture/` |
| @G8LD | AS | `docs/adr/`, `docs/architecture/` (with @PaulPerigault) |
| @MatRom-03 | QE | `tests/`, `docs/qa/` |
| @LiberiBg | SE | `services/`, `frontend/`, `packages/` |
| @Pawpawzz | PO | product decisions, priorities, acceptance of user stories (`status/needs-decision`) |
| @BadiiiiX | BA | business rules, acceptance criteria, demo scenario (`role/ba`) |

@PaulPerigault also covers QE/AS work on the infrastructure side but is only assigned to `role/ops` issues.

Merge rule: PR required, 0 approvals, required checks green. CODEOWNERS routes review requests; it does not block merges.

## Repository map

```
infra/
  bootstrap/            # state bucket, KMS, GitHub OIDC roles — the ONLY local apply
  modules/<name>/       # independent bricks (see .kiro/steering/iac.md)
  stacks/foundation/    # KMS, security baseline, observability, budgets
  stacks/platform/      # edge, identity, api, data, compute, ai, notifications
  envs/<env>/           # backend.hcl + terraform.tfvars per environment
services/<function>/    # Lambda code (SE)
frontend/               # SPA (SE)
packages/contracts/     # OpenAPI + shared schemas (contract between SE and QE)
tests/{smoke,perf,e2e,security}/
policies/               # custom Checkov policies
docs/{adr,architecture,runbooks,qa,backlog,prompts}/
.github/{workflows,actions,ISSUE_TEMPLATE}/
```

## Non-negotiable rules

1. **Everything as code.** No console changes. No local `tofu apply` except `infra/bootstrap` (run by a human). All other applies go through CI (GitOps).
2. **Security by default** — see `.kiro/steering/security.md`. Least privilege, CMK encryption, TLS only, no public buckets, no secrets in code, state outputs or logs.
3. **Independent bricks.** A module never discovers another module's resources; inputs are explicit, outputs are documented. Same rule for services.
4. **No change without tests.** `task check` must pass before any commit.
5. **Pin everything.** Tools in `.mise.toml`, providers in `versions.tf` + lock file, GitHub Actions by full commit SHA.
6. **Never read, print or copy** `.env`, `~/.aws/*`, `*.tfstate`, tokens or credentials.
7. **No tool attribution** in commits, PRs or code comments (no `Co-Authored-By`, no "Generated with").
8. **Language.** Code, identifiers, comments, commit messages and branch names in English. Issues, PR descriptions and team docs in French.
9. **Prefer deletion over dead code**, explicit over clever, boring over novel. Every non-obvious decision gets an ADR in `docs/adr/`.

## Git workflow

- `main` = production, `develop` = integration (default branch). Both protected by rulesets.
- Branch from `develop`: `<type>/<issue-number>-<short-slug>` (e.g. `feat/12-tickets-store`).
- Conventional Commits. Types: `feat fix docs style refactor perf test build ci chore revert`. Scopes: `bootstrap edge identity api data ai notif sla obs sec ci cd qa docs deps app front contracts release`.
- One logical change per commit. Squash-merge into `develop`; PR title must be a valid conventional commit and the body must contain `Closes #<n>`.
- Releases: `develop` → `main` via release PR; release-please generates tags and `CHANGELOG.md`.

## Commands (Taskfile)

| Command | Purpose |
|---|---|
| `task setup` | install pinned toolchain (mise) and git hooks (lefthook) |
| `task check` | fmt + lint + security + unit tests (the pre-commit gate) |
| `task test:unit` / `task test:integration ENV=dev` | `tofu test` with mocks / against the dev account |
| `task plan ENV=dev STACK=platform` | read-only plan |
| `task docs` | regenerate module READMEs (terraform-docs) |
| `task smoke ENV=dev` / `task perf ENV=dev` | Hurl smoke tests / k6 thresholds |

## Environments

| Env | Branch | AWS | Prefix |
|---|---|---|---|
| dev | `develop` | workshop account, `eu-west-3` (+ `us-east-1` for CloudFront WAF/ACM) | `sc-dev` |
| prod | `main` (manual approval) | same account during the workshop (ADR-0002), separate account later | `sc-prod` |

## Definition of Done

- Acceptance criteria of the issue covered by automated tests named after them (`US04-AC2 …`).
- `task check` green locally and in CI; plan reviewed; no new Checkov/Trivy finding without a justified skip comment.
- Module README regenerated; ADR written if a decision was made; issue updated with a short progress note.

---
inclusion: manual
---

# Git & GitHub workflow details

## Labels (taxonomy)
- `type/epic`, `type/story`, `type/enabler` (technical story), `type/nfr`, `type/bug`, `type/chore`, `type/spike`
- `area/infra`, `area/ci-cd`, `area/security`, `area/observability`, `area/qa`, `area/app`, `area/front`, `area/ai`, `area/docs`
- `role/ops`, `role/qe`, `role/as`, `role/se`, `role/ba`
- `priority/must`, `priority/should`, `priority/could`, `priority/wont` (MoSCoW)
- `size/xs|s|m|l`
- `status/blocked`, `status/in-progress`, `status/needs-decision`
- `drift`, `dependencies`, `security`

## Issue structure
- Epics `E0..E9` are parent issues; stories/enablers are **sub-issues** of exactly one epic.
- Body sections (French): Contexte · User story (En tant que / je veux / afin de) · Critères d'acceptation (Gherkin, IDs `AC1..n`) · Exigences non fonctionnelles · Notes techniques / décisions · Dépendances · Definition of Done.
- IDs in titles: `US-xx` user-facing stories, `EN-xx` technical enablers, `NFR-xx` cross-cutting requirements, `RF-xx` business rules.

## Project board (GitHub Projects v2)
Fields: Status (Backlog, Ready, In progress, In review, Done), Priority (MoSCoW), Epic, Role, Size. Views: board by Status, table by Epic, "OPS/QE" filtered view.

## PR template (French body)
Résumé · Issue liée (`Closes #n`) · Changements · Tests ajoutés/exécutés · Impact sécurité (IAM/KMS/réseau/données) · Plan OpenTofu (résumé) · Coût (Infracost) · Checklist DoD.

## Branch protection (rulesets)
- `develop`: PR required, required checks, linear history, block force-push and deletion, squash only.
- `main`: PR required from `develop`/release-please only (`guard-main` check), required checks, block force-push and deletion, merge commit allowed for release PRs.

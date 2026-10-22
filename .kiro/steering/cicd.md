---
inclusion: fileMatch
fileMatchPattern: ".github/**"
---

# CI/CD conventions (GitHub Actions, GitOps)

## Workflows
| File | Trigger | Jobs |
|---|---|---|
| `ci.yml` | pull_request, push develop/main | `pr-title` (conventional), `lint` (fmt, tflint, actionlint, zizmor), `security` (checkov, trivy, gitleaks), `test` (tofu test unit, app unit tests if changed), `docs` (terraform-docs check) |
| `iac-plan.yml` | pull_request touching `infra/**` | OIDC read-only role → plan per stack for dev (and prod when base is `main`) → sticky PR comment (summary) + Infracost diff |
| `iac-apply.yml` | push develop → env `dev`; push main → env `prod` | plan → upload encrypted plan artifact → apply **that exact plan** in a job bound to the GitHub environment (prod requires approval) → `check` blocks/smoke |
| `app-deploy.yml` | push develop/main touching `services/**`, `frontend/**` | build per service (arm64 zip) → upload to artifacts bucket (key = git SHA) → `update-function-code` + `publish-version` + update alias `live`; SPA build → `s3 sync --delete` + CloudFront invalidation; smoke; rollback alias on failure |
| `post-deploy.yml` | workflow_run of apply/deploy on develop | Hurl smoke + security tests, k6 thresholds, (optional) ZAP baseline |
| `drift.yml` | schedule nightly + manual | `tofu plan -detailed-exitcode` per stack/env → open/update issue labelled `drift` |
| `release.yml` | push main | release-please (tag + CHANGELOG) |
| `guard-main.yml` | pull_request to main | fails unless head branch is `develop` or `release-please--*` |

Reusable workflow `_tofu.yml` (inputs: env, stack, mode plan|apply) and composite actions in `.github/actions/` (`setup-toolchain` via mise, `aws-oidc`). No duplicated job definitions.

## Security rules for workflows
- Top-level `permissions: {}`; each job declares only what it needs (`id-token: write` only in AWS jobs, `pull-requests: write` only for commenting).
- Pin every action to a full commit SHA with a `# vX.Y.Z` comment.
- `actions/checkout` with `persist-credentials: false`. Never `pull_request_target`. Untrusted context (`github.event.*.title`, branch names) only through `env:` never inline in `run:`.
- `concurrency` group per env/stack with `cancel-in-progress: false` for apply, `true` for CI. `timeout-minutes` on every job.
- AWS: `aws-actions/configure-aws-credentials` with role ARN from environment **variables** (`vars.AWS_PLAN_ROLE_ARN`, `vars.AWS_APPLY_ROLE_ARN`), never secrets/keys.
- Required status check names are stable (`ci / lint`, `ci / security`, `ci / test`, `ci / pr-title`, `ci / docs`); renaming a job is a breaking change for rulesets.

## Toolchain
- `.mise.toml` is the single source of tool versions, used locally and in CI (`jdx/mise-action`). Locally it loads `.env` (`[env] _.file = ".env"`); CI never has a `.env`.
- Tools to pin: opentofu, tflint, checkov, trivy, gitleaks, terraform-docs, actionlint, zizmor, lefthook, task, awscli, hurl, k6, node (+ pnpm), infracost.
- Taskfile is the single entry point: CI calls `task <target>`, never re-implements commands.
- Lefthook: pre-commit (fmt, gitleaks, tflint on staged), commit-msg (commitlint), pre-push (`task check`).
- release-please: `release-type: simple`, changelog sections per conventional type.

---
inclusion: always
---

# Security invariants (DevSecOps)

## Identity and access
- Least privilege: policies built with `aws_iam_policy_document`; no `Action = "*"`, no `Resource = "*"` except where the API has no resource-level support (comment + Checkov skip with reason).
- Every service-principal trust or resource policy carries `aws:SourceArn` / `aws:SourceAccount` conditions (confused deputy).
- Every IAM role created by OpenTofu has the project **permissions boundary** attached; the CI apply role can only create roles that carry it.
- GitHub → AWS only via OIDC. Trust `sub` pinned to `repo:<org>/<repo>:environment:<env>` (apply) or `repo:<org>/<repo>:pull_request` (read-only plan). No long-lived keys anywhere.

## Data
- Encryption at rest with customer-managed KMS keys (rotation on); TLS enforced (`aws:SecureTransport`) on every bucket policy.
- S3: Block Public Access (account + bucket), `BucketOwnerEnforced`, versioning, lifecycle.
- PII (email, name, ticket content, chat transcripts): minimal collection, TTL/retention defined, deletion path exists, never logged in clear (Powertools/log redaction), Guardrail PII masking for the assistant.
- OpenTofu state: S3 backend with `use_lockfile`, SSE-KMS, plus OpenTofu client-side state and plan encryption (`encryption` block, `aws_kms` key provider, `enforced = true`).

## Secrets
- No secret in code, tfvars, outputs, logs or workflow files. Runtime secrets in SSM Parameter Store SecureString or Secrets Manager, read at runtime with IAM.
- Local secrets only in `.env` (git-ignored) — agents must never read it.
- gitleaks runs in pre-commit and CI; GitHub secret scanning + push protection enabled.

## Supply chain
- Tools pinned in `.mise.toml`; provider lock file committed (multi-platform hashes); Actions pinned by SHA; Renovate/Dependabot keep them fresh.
- Workflows: top-level `permissions: {}`, job-level minimal; `actions/checkout` with `persist-credentials: false`; no `pull_request_target`; no untrusted input interpolated in `run:` (use env vars). zizmor + actionlint in CI.

## Detection
- CloudTrail, GuardDuty, Security Hub FSBP, Config, Access Analyzer (toggles if already provided by the account).
- Alarms on auth failures spikes, WAF blocks, 5xx, DLQ depth; WAF + API access logs retained and KMS-encrypted.

## Findings policy
- Checkov / Trivy / tflint findings are fixed, not silenced. A skip needs an inline justification `# checkov:skip=<ID>: <reason>` and is listed in the PR description.

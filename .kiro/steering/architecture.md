---
inclusion: always
---

# Target architecture v3 (serverless, us-east-1 for the workshop — ADR-0013)

Each decision below is binding; changing one requires a new ADR in `docs/adr/`.

## Request path
- **No custom domain is available (decision 2026-10-22).** The app is served on the `*.cloudfront.net` URL; `enable_custom_domain` stays in code (ACM us-east-1 + Route 53) but is `false`. No Route 53 zone.
- **CloudFront is the single entry point for users.** Behaviours: `/*` → private S3 SPA bucket (OAC), `/api/*` → API Gateway origin (caching disabled, `Authorization` forwarded via origin request policy). Same origin ⇒ no CORS.
- **API Gateway REST API (regional), not HTTP API** (ADR). Without a domain, the `execute-api` URL cannot be disabled, so the API must be protected on its own: only REST APIs accept a **regional WAF web ACL**, request validation (JSON Schema models), stage/method throttling and usage limits. The extra cost per million requests is negligible at campus scale.
- **Two WAF web ACLs**: CLOUDFRONT scope (us-east-1) on the distribution, REGIONAL on the API stage. Both: AWS managed rule groups (Common, KnownBadInputs, IpReputation, AnonymousIp), body size limit; the regional ACL carries the rate-based rules aggregated on the `Authorization` header (per user) and per IP (RF04), so the limit applies whichever URL is used. WAF logs → CloudWatch Logs `aws-waf-logs-*`.
- Response headers policy: HSTS, CSP, X-Content-Type-Options, Referrer-Policy, frame-ancestors none. Viewer protocol `redirect-to-https`, TLSv1.2_2021 minimum.

## Identity
- Cognito User Pool, groups `student` and `admin`, app client **authorization code + PKCE only**, no client secret (SPA), short access token (≤ 60 min), refresh token rotation, MFA required for `admin`, threat protection if available.
- Entra ID federation behind `enable_entra_federation` (OIDC IdP). Pre-token-generation trigger enforces the approved email domain and maps groups.
- **API authorization = native Cognito User Pool authorizer of the REST API** (validates signature, expiry, issuer, audience; tokens issued by Cognito also cover federated Entra users). No custom Lambda authorizer. Admin-only methods additionally checked in handlers from `cognito:groups`.
- Object-level authorization (OWASP API1/BOLA): a student's identity always comes from the JWT `sub`, never from the request; queries are keyed by it.

## Compute
- Lambda, **arm64**, one function per bounded use case (`tickets`, `kpi`, `chat`, `escalation`, `notifier`, `kb-sync`, `kpi-aggregator`, `pre-token`), **one IAM role per function**, active tracing, explicit log group (KMS, retention), alias `live`, async failures → SQS DLQ / on-failure destination.
- **No VPC**: every dependency is a regional AWS API reached over TLS with IAM auth; a VPC would add NAT cost and cold starts with no security gain (ADR).
- Runtime chosen by SE; infra builds/deploys artifacts only. Infra owns configuration, the app pipeline owns code (`ignore_changes` on code in OpenTofu).

## Data
- `tickets` table (on-demand, PITR, deletion protection in prod, CMK): item collection per ticket (`TICKET#id` / `META`, `EVENT#ts` for the audit trail of US01). GSIs: by owner (`sub`) + createdAt, by status + createdAt. Never `Scan`.
- `chat-sessions` table, separate (different retention): TTL attribute for GDPR purge (US08).
- `kpi` table: daily aggregates (per status/category, resolution time sums) maintained from the tickets stream by `kpi-aggregator`; `kpi` reads O(days) items (US05).
- Attachments bucket: private, SSE-KMS (bucket key), versioning, TLS-only policy, lifecycle; uploads via **presigned POST** with `content-length-range` ≤ 10 MB and image content-type conditions; **GuardDuty Malware Protection for S3** tags objects, only clean objects are served.

## Events and SLA
- Tickets stream → `notifier` and `kpi-aggregator` with **event filters** (only relevant changes), batch item failure reporting, bisect on error, on-failure destination SQS.
- **SLA (RF01)**: when a ticket is created, `tickets` creates a one-time **EventBridge Scheduler** schedule `at(created+24h)` with `ActionAfterCompletion=DELETE` targeting `escalation`, which is idempotent (no-op if the ticket left `Ouvert`). No hourly scan.
- Security-category tickets → priority `critique` + immediate SNS alert to admins.
- Notifications: SES (sandbox in workshop ⇒ verified identities) for students, SNS topic for ops/admin alerts.

## AI assistant
- Bedrock Knowledge Base with **S3 Vectors** as vector store (no OpenSearch Serverless: cost floor and provisioning time). If S3 Vectors/KB is unavailable in the region, fallback documented in ADR.
- Source documents bucket → S3 event → `kb-sync` → `StartIngestionJob` (US07); ingestion status logged.
- **Guardrail**: denied topics, PII masking, prompt-attack filter, **contextual grounding check** with thresholds; below threshold ⇒ answer "je ne sais pas" + offer ticket escalation (RF03, US10).
- Model ID is a variable; use a **cross-region inference profile of the deployment region**: `us.*` during the workshop (ADR-0013, test data only), an **EU profile** for a real production so inference stays in the EU. Model invocation logging disabled or to a CMK-encrypted bucket with short retention (GDPR).

## Cross-cutting
- KMS CMKs per domain (`data`, `logs`, `ai`), rotation on, explicit key policies.
- Observability: structured JSON logs, X-Ray, CloudWatch dashboard, alarms (5xx, latency p95, throttles, DLQ depth, WAF blocks, Lambda errors) → SNS. AWS Budget alert.
- Security baseline module with toggles (account-level services may already exist in the workshop account): CloudTrail, GuardDuty, Security Hub (FSBP), AWS Config, IAM Access Analyzer.
- Multi-account ready (one backend + tfvars per env); workshop runs dev and prod in one account, isolated by prefix and state key (ADR).

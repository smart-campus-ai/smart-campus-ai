---
inclusion: fileMatch
fileMatchPattern: "tests/**"
---

# Test strategy (QE)

## Pyramid
| Level | Tool | Where | When |
|---|---|---|---|
| Static | tofu fmt/validate, tflint, actionlint, zizmor | repo | pre-commit, CI |
| Policy | Checkov (+ custom `policies/`), Trivy config, gitleaks | repo | pre-push, CI |
| Unit IaC | `tofu test` + `mock_provider` (`command = plan`) | `infra/modules/*/tests/unit.tftest.hcl` | CI on every PR |
| Integration IaC | `tofu test` (`command = apply`, ephemeral resources) | `infra/modules/*/tests/integration.tftest.hcl` | manual / nightly on dev |
| Contract | OpenAPI in `packages/contracts`; Hurl asserts status + schema | `tests/smoke` | post-deploy |
| Smoke + security | Hurl | `tests/smoke`, `tests/security` | post-deploy dev, gate for prod |
| Performance (NFR < 2 s) | k6 thresholds `p(95)<2000`, `http_req_failed<1%` | `tests/perf` | post-deploy dev |
| E2E | Playwright (critical journeys only) | `tests/e2e` | post-deploy dev |
| DAST (optional) | OWASP ZAP baseline on CloudFront URL | CI | nightly dev |

## Mandatory security test cases
- No token → 401; invalid/expired token → 401; student on admin route → 403.
- **BOLA**: student A cannot read/update student B's ticket (expect 403/404, never 200).
- Upload > 10 MB or non-image content type → rejected by presigned POST policy.
- WAF: burst above rate limit → 429/403 on dev; known-bad payload blocked.
- Chat: out-of-scope question → grounded refusal + escalation offer (no hallucinated answer).
- HTTPS redirect and security headers present (HSTS, CSP, nosniff).

## Conventions
- Test names start with the acceptance criterion ID: `US04-AC2 rejects ticket without title`.
- `docs/qa/traceability.md`: US/RF → acceptance criteria → test IDs → status (generated/updated with each PR).
- Test users (dev only) come from IaC behind `enable_test_users`; credentials in SSM SecureString, read by CI via OIDC — never in the repo.
- Tests are deterministic and idempotent; every test creates and cleans its own data (prefix `qa-<run-id>`).

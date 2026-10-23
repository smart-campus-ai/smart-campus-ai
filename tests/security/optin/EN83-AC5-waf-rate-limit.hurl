# EN83-AC5 / RF04-AC2 a burst above the rate limit is blocked: 429 or 403 (SEC-009 CloudFront, SEC-010 execute-api).
# OPT-IN, DEV ONLY: not part of the default glob, never run on prod, never in parallel with other suites.
#
# Mechanism: each request is retried (up to 600 times, one every 200 ms, about 2 minutes, at most 600 requests per URL)
# until the response is 403 or 429. The test fails if no block shows up. WAF rate-based rules need up to about
# 30 s to start blocking, which is why the burst is spread over time instead of sent at once.
# Requests are unauthenticated (401 until blocked) so no test user token is consumed or blocked.
#
# Side effect: the runner IP stays blocked until its rate falls back under the threshold (a few minutes).
# Run this suite LAST and wait before re-running anything else from the same IP.
#
# Variables: spa_url, api_url.
# Run: hurl --test --variables-file tests/smoke/vars.dev.properties tests/security/optin/EN83-AC5-waf-rate-limit.hurl

# EN83-AC5 burst on the CloudFront URL gets blocked (SEC-009)
GET {{spa_url}}/api/tickets
[Options]
retry: 600
retry-interval: 200ms
HTTP *
[Asserts]
status toString matches /^(403|429)$/

# EN83-AC5 burst on the direct execute-api URL gets blocked (SEC-010)
GET {{api_url}}/api/tickets
[Options]
retry: 600
retry-interval: 200ms
HTTP *
[Asserts]
status toString matches /^(403|429)$/

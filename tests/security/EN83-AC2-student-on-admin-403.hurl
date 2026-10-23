# EN83-AC2 / US01-AC5 / US05-AC3 a student on an admin-only route gets 403 (SEC-004, SEC-016).
# The admin positive control proves the 403 comes from the group check, not from a wrong route.
# Variables: spa_url, api_url, student_a_token, admin_token.
# Assumed admin-only route (to align with packages/contracts): GET /api/kpi.
# If CloudFront turns API 403 into the SPA fallback page (custom error response), the CloudFront
# assertion below fails on purpose: it reveals an edge misconfiguration.

# EN83-AC2 admin reads KPI (positive control)
GET {{spa_url}}/api/kpi
Authorization: Bearer {{admin_token}}
HTTP 200

# EN83-AC2 student on admin route gets 403 (CloudFront)
GET {{spa_url}}/api/kpi
Authorization: Bearer {{student_a_token}}
HTTP 403
[Asserts]
header "Content-Type" contains "application/json"

# EN83-AC2 student on admin route gets 403 (execute-api)
GET {{api_url}}/api/kpi
Authorization: Bearer {{student_a_token}}
HTTP 403
[Asserts]
header "Content-Type" contains "application/json"

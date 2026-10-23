# EN83-AC1 The API answers on its base endpoints, through CloudFront (/api/*) and on the direct execute-api URL.
# Covers SMK-004 (student lists own tickets) and SMK-010 (admin reads KPI).
# Variables: spa_url, api_url, student_a_token, admin_token (tokens injected at run time, never committed).
# Assumed routes (to align with packages/contracts): GET /api/tickets, GET /api/kpi.

# EN83-AC1 API is reachable and protected through CloudFront (authorizer answers, not the SPA fallback)
GET {{spa_url}}/api/tickets
HTTP 401
[Asserts]
header "Content-Type" contains "application/json"
jsonpath "$.message" exists

# EN83-AC1 API is reachable and protected on the direct execute-api URL
GET {{api_url}}/api/tickets
HTTP 401
[Asserts]
header "Content-Type" contains "application/json"
jsonpath "$.message" exists

# EN83-AC1 US03-AC1 student lists own tickets through CloudFront
GET {{spa_url}}/api/tickets
Authorization: Bearer {{student_a_token}}
HTTP 200
[Asserts]
header "Content-Type" contains "application/json"

# EN83-AC1 US03-AC1 student lists own tickets on the direct execute-api URL
GET {{api_url}}/api/tickets
Authorization: Bearer {{student_a_token}}
HTTP 200
[Asserts]
header "Content-Type" contains "application/json"

# EN83-AC1 US05-AC1 admin reads KPI aggregates
GET {{spa_url}}/api/kpi
Authorization: Bearer {{admin_token}}
HTTP 200
[Asserts]
header "Content-Type" contains "application/json"

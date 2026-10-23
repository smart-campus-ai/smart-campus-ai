# EN83-AC2 / EN-32-AC1 protected methods answer 401 without a token (SEC-001).
# Checked through CloudFront (/api/*) and on the direct execute-api URL.
# Variables: spa_url, api_url, ticket_category.
# Assumed routes (to align with packages/contracts): /api/tickets, /api/kpi.

# EN83-AC2 list tickets without token gets 401 (CloudFront)
GET {{spa_url}}/api/tickets
HTTP 401

# EN83-AC2 list tickets without token gets 401 (execute-api)
GET {{api_url}}/api/tickets
HTTP 401

# EN83-AC2 create ticket without token gets 401 (CloudFront)
POST {{spa_url}}/api/tickets
Content-Type: application/json
{
  "title": "qa-{{newUuid}}",
  "description": "must never be stored",
  "category": "{{ticket_category}}"
}
HTTP 401

# EN83-AC2 create ticket without token gets 401 (execute-api)
POST {{api_url}}/api/tickets
Content-Type: application/json
{
  "title": "qa-{{newUuid}}",
  "description": "must never be stored",
  "category": "{{ticket_category}}"
}
HTTP 401

# EN83-AC2 KPI without token gets 401 (CloudFront)
GET {{spa_url}}/api/kpi
HTTP 401

# EN83-AC2 KPI without token gets 401 (execute-api)
GET {{api_url}}/api/kpi
HTTP 401

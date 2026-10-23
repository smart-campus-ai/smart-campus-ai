# US04-AC1 create ticket returns 201 with status "Ouvert" (SMK-001)
# US04-AC2 rejects ticket without title with 400 (SMK-002)
# Variables: spa_url, student_a_token, ticket_category.
# Data: titles are prefixed "qa-"; the API has no delete route, the nightly sweep removes stale qa-* tickets.
# Assumed contract (to align with packages/contracts): POST /api/tickets {title, description, category} -> 201 {id, status, title}.

# US04-AC1 create ticket returns 201 with status Ouvert
POST {{spa_url}}/api/tickets
Authorization: Bearer {{student_a_token}}
Content-Type: application/json
{
  "title": "qa-{{newUuid}}",
  "description": "qa smoke test ticket",
  "category": "{{ticket_category}}"
}
HTTP 201
[Asserts]
jsonpath "$.status" == "Ouvert"
jsonpath "$.id" exists
[Captures]
ticket_id: jsonpath "$.id"

# US04-AC1 the created ticket can be read back by its owner
GET {{spa_url}}/api/tickets/{{ticket_id}}
Authorization: Bearer {{student_a_token}}
HTTP 200
[Asserts]
jsonpath "$.id" == "{{ticket_id}}"
jsonpath "$.status" == "Ouvert"

# US04-AC2 rejects ticket without title (request validation, EN-33 AC2)
POST {{spa_url}}/api/tickets
Authorization: Bearer {{student_a_token}}
Content-Type: application/json
{
  "description": "qa smoke test ticket without title",
  "category": "{{ticket_category}}"
}
HTTP 400

# US04-AC2 rejects ticket with an empty title
POST {{spa_url}}/api/tickets
Authorization: Bearer {{student_a_token}}
Content-Type: application/json
{
  "title": "",
  "description": "qa smoke test ticket with empty title",
  "category": "{{ticket_category}}"
}
HTTP 400

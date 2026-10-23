# EN83-AC3 / US03-AC3 BOLA: student A can neither read, update nor list student B's ticket (SEC-005, SEC-006).
# Never 200 for A on B's ticket: 403 or 404 only, and no data of B in the response.
# Variables: spa_url, api_url, student_a_token, student_b_token, ticket_category.
# Data: B's ticket title is prefixed "qa-"; the API has no delete route, the nightly sweep removes stale qa-* tickets.
# Assumed contract (to align with packages/contracts): POST /api/tickets -> 201 {id, title}; GET and PATCH /api/tickets/{id}
# (PATCH body {"description": "..."}); GET /api/tickets lists the caller's tickets.

# EN83-AC3 B creates a ticket
POST {{spa_url}}/api/tickets
Authorization: Bearer {{student_b_token}}
Content-Type: application/json
{
  "title": "qa-{{newUuid}}",
  "description": "qa-b-original",
  "category": "{{ticket_category}}"
}
HTTP 201
[Captures]
b_ticket_id: jsonpath "$.id"
b_title: jsonpath "$.title"

# EN83-AC3 B reads own ticket (positive control)
GET {{spa_url}}/api/tickets/{{b_ticket_id}}
Authorization: Bearer {{student_b_token}}
HTTP 200
[Asserts]
jsonpath "$.id" == "{{b_ticket_id}}"

# EN83-AC3 B updates own ticket (positive control for the update route)
PATCH {{spa_url}}/api/tickets/{{b_ticket_id}}
Authorization: Bearer {{student_b_token}}
Content-Type: application/json
{
  "description": "qa-b-updated"
}
HTTP 200

# EN83-AC3 A cannot read B's ticket (CloudFront)
GET {{spa_url}}/api/tickets/{{b_ticket_id}}
Authorization: Bearer {{student_a_token}}
HTTP *
[Asserts]
status >= 403
status <= 404
body not contains "{{b_title}}"
body not contains "qa-b-updated"

# EN83-AC3 A cannot read B's ticket (execute-api)
GET {{api_url}}/api/tickets/{{b_ticket_id}}
Authorization: Bearer {{student_a_token}}
HTTP *
[Asserts]
status >= 403
status <= 404
body not contains "{{b_title}}"
body not contains "qa-b-updated"

# EN83-AC3 A cannot update B's ticket (CloudFront)
PATCH {{spa_url}}/api/tickets/{{b_ticket_id}}
Authorization: Bearer {{student_a_token}}
Content-Type: application/json
{
  "description": "qa-tampered-by-a"
}
HTTP *
[Asserts]
status >= 403
status <= 404

# EN83-AC3 A cannot update B's ticket (execute-api)
PATCH {{api_url}}/api/tickets/{{b_ticket_id}}
Authorization: Bearer {{student_a_token}}
Content-Type: application/json
{
  "description": "qa-tampered-by-a"
}
HTTP *
[Asserts]
status >= 403
status <= 404

# EN83-AC3 A's ticket list does not contain B's ticket
GET {{spa_url}}/api/tickets
Authorization: Bearer {{student_a_token}}
HTTP 200
[Asserts]
body not contains "{{b_ticket_id}}"
body not contains "{{b_title}}"

# EN83-AC3 B's ticket was not modified by A's attempt
GET {{spa_url}}/api/tickets/{{b_ticket_id}}
Authorization: Bearer {{student_b_token}}
HTTP 200
[Asserts]
jsonpath "$.description" == "qa-b-updated"

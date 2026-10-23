# EN83-AC2 a foreign Origin is never allowed by CORS (architecture: same origin, no CORS configured).
# Variables: spa_url, api_url, student_a_token.
# The response status is not constrained (403/404/401 depending on the layer); only the absence of CORS grants matters.

# EN83-AC2 preflight from a foreign origin gets no CORS grant (CloudFront)
OPTIONS {{spa_url}}/api/tickets
Origin: https://evil.example
Access-Control-Request-Method: GET
Access-Control-Request-Headers: authorization
HTTP *
[Asserts]
header "Access-Control-Allow-Origin" not exists
header "Access-Control-Allow-Credentials" not exists

# EN83-AC2 preflight from a foreign origin gets no CORS grant (execute-api)
OPTIONS {{api_url}}/api/tickets
Origin: https://evil.example
Access-Control-Request-Method: GET
Access-Control-Request-Headers: authorization
HTTP *
[Asserts]
header "Access-Control-Allow-Origin" not exists
header "Access-Control-Allow-Credentials" not exists

# EN83-AC2 authenticated request from a foreign origin is not reflected (CloudFront)
GET {{spa_url}}/api/tickets
Origin: https://evil.example
Authorization: Bearer {{student_a_token}}
HTTP *
[Asserts]
header "Access-Control-Allow-Origin" not exists
header "Access-Control-Allow-Credentials" not exists

# EN83-AC2 authenticated request from a foreign origin is not reflected (execute-api)
GET {{api_url}}/api/tickets
Origin: https://evil.example
Authorization: Bearer {{student_a_token}}
HTTP *
[Asserts]
header "Access-Control-Allow-Origin" not exists
header "Access-Control-Allow-Credentials" not exists

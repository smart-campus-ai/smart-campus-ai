# EN83-AC2 / EN-32-AC2 invalid tokens answer 401 (SEC-002).
# The expired-token case (SEC-003) needs a real expired JWT: see optin/EN83-AC2-expired-token-401.hurl.
# Variables: spa_url, api_url, student_a_token.
# No JWT-shaped literal is committed on purpose (secret scanners); the malformed values below are not JWTs.

# EN83-AC2 garbage bearer value gets 401 (CloudFront)
GET {{spa_url}}/api/tickets
Authorization: Bearer not-a-jwt
HTTP 401

# EN83-AC2 garbage bearer value gets 401 (execute-api)
GET {{api_url}}/api/tickets
Authorization: Bearer not-a-jwt
HTTP 401

# EN83-AC2 three-part value with an invalid signature gets 401 (CloudFront)
GET {{spa_url}}/api/tickets
Authorization: Bearer aaaa.bbbb.cccc
HTTP 401

# EN83-AC2 three-part value with an invalid signature gets 401 (execute-api)
GET {{api_url}}/api/tickets
Authorization: Bearer aaaa.bbbb.cccc
HTTP 401

# EN83-AC2 valid token with a tampered signature gets 401 (CloudFront)
# A character is appended to the real token, so header and payload stay valid but the signature does not.
GET {{spa_url}}/api/tickets
Authorization: Bearer {{student_a_token}}x
HTTP 401

# EN83-AC2 valid token with a tampered signature gets 401 (execute-api)
GET {{api_url}}/api/tickets
Authorization: Bearer {{student_a_token}}x
HTTP 401

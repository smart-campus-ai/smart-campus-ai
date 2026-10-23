# EN83-AC1 SPA answers over HTTPS and plain HTTP is redirected to HTTPS (EN-21 AC1, SEC-014).
# Variables: spa_url, spa_host. Read-only, no data created.

# EN83-AC1 SPA entry point serves the application over HTTPS
GET {{spa_url}}/
HTTP 200
[Asserts]
header "Content-Type" contains "text/html"

# EN83-AC1 plain HTTP is redirected to HTTPS (redirects are not followed by default)
GET http://{{spa_host}}/
HTTP 301
[Asserts]
header "Location" startsWith "https://"

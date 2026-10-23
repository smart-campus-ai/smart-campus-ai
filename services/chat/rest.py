"""REST proxy (payload 1.0) request/response helpers.

The function returns ``{statusCode, headers, body}`` with ``body`` as a JSON
string (infra/app contract, section 4). Same origin as the SPA: no CORS headers.
"""

from __future__ import annotations

import json

from errors import ApiError, validation_error

_JSON_HEADERS = {"Content-Type": "application/json"}


def parse_json_body(event: dict) -> object:
    raw = event.get("body")
    if raw is None or raw == "":
        raise validation_error("A JSON body is required.")
    if event.get("isBase64Encoded"):
        import base64

        raw = base64.b64decode(raw).decode("utf-8")
    try:
        return json.loads(raw)
    except (ValueError, TypeError):
        raise validation_error("Request body is not valid JSON.")


def query_params(event: dict) -> dict:
    return event.get("queryStringParameters") or {}


def path_params(event: dict) -> dict:
    return event.get("pathParameters") or {}


def json_response(status_code: int, payload: object, extra_headers: dict | None = None) -> dict:
    headers = dict(_JSON_HEADERS)
    if extra_headers:
        headers.update(extra_headers)
    return {
        "statusCode": status_code,
        "headers": headers,
        "body": json.dumps(payload),
    }


def no_content() -> dict:
    return {"statusCode": 204, "headers": {}, "body": ""}


def error_response(error: ApiError, request_id: str | None = None) -> dict:
    return json_response(error.status_code, error.to_body(request_id))

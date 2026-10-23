"""Minimal REST proxy response helpers for the admin resync endpoint."""

from __future__ import annotations

import json

from errors import ApiError

_JSON_HEADERS = {"Content-Type": "application/json"}


def json_response(status_code: int, payload: object) -> dict:
    return {"statusCode": status_code, "headers": dict(_JSON_HEADERS), "body": json.dumps(payload)}


def error_response(error: ApiError, request_id: str | None = None) -> dict:
    return json_response(error.status_code, error.to_body(request_id))

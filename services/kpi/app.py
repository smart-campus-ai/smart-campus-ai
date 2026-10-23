"""Lambda entrypoint for the ``kpi`` function (handler = ``app.handler``).

Route: GET /kpi (admin-only, US05-AC5). The native Cognito authorizer has already
validated the token; the handler additionally checks the ``admin`` group and reads
daily aggregates from the ``kpi`` table (never the ``tickets`` table, US05-AC4).
"""

from __future__ import annotations

import logging

import rest
from auth import caller_from_event, require_admin
from errors import ApiError, internal_error, not_found_fallback
from service import KpiService

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _build_service() -> KpiService:
    from adapters import build_from_env

    store = build_from_env()
    return KpiService(store)


def _route(event: dict, service: KpiService) -> dict:
    method = (event.get("httpMethod") or "").upper()
    resource = event.get("resource") or event.get("path") or ""
    caller = caller_from_event(event)

    if resource.endswith("/kpi") and method == "GET":
        require_admin(caller)  # US05-AC5
        result = service.dashboard(caller, rest.query_params(event))
        return rest.json_response(200, result)

    raise not_found_fallback()


def handler(event: dict, context: object) -> dict:
    request_id = getattr(context, "aws_request_id", None)
    try:
        service = _build_service()
        return _route(event, service)
    except ApiError as exc:
        return rest.error_response(exc, request_id)
    except Exception:  # noqa: BLE001 — never leak internals
        logger.exception("Unhandled error in kpi handler")
        return rest.error_response(internal_error(), request_id)

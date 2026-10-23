"""Lambda entrypoint for the ``chat`` function (handler = ``app.handler``).

Routes (OpenAPI, tag ``chat``): POST /chat/messages, GET /chat/sessions,
DELETE /chat/sessions, GET /chat/sessions/{sessionId}. The native Cognito
authorizer has already validated the token; claims are in
``event.requestContext.authorizer.claims``. The caller identity is the JWT ``sub``.
"""

from __future__ import annotations

import logging
import os

import rest
from auth import caller_from_event
from errors import ApiError, internal_error, not_found
from service import ChatService

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _thresholds():
    # Imported here so the domain import stays lazy-free for tests importing app.
    import domain

    grounding = float(os.environ.get("GROUNDING_THRESHOLD", "0.7"))
    relevance = float(os.environ.get("RELEVANCE_THRESHOLD", "0.7"))
    # Raises ValueError if outside [0, 1] (RF03-AC5); surfaced as a 500 at runtime,
    # but the real guard is the OpenTofu variable validation on the module inputs.
    return domain.Thresholds(grounding=grounding, relevance=relevance)


def _build_service() -> ChatService:
    # Imported lazily so unit tests never need boto3 or AWS configuration.
    from adapters import build_from_env

    store, knowledge_base, assistant, metrics = build_from_env()
    ttl_days = int(os.environ.get("SESSION_TTL_DAYS", "30"))
    return ChatService(
        store,
        knowledge_base,
        assistant,
        thresholds=_thresholds(),
        ttl_days=ttl_days,
        metrics=metrics,
    )


def _route(event: dict, service: ChatService) -> dict:
    method = (event.get("httpMethod") or "").upper()
    resource = event.get("resource") or event.get("path") or ""
    caller = caller_from_event(event)

    if resource.endswith("/chat/messages") and method == "POST":
        body = rest.parse_json_body(event)
        result = service.send_message(caller, body)
        return rest.json_response(200, result)

    if resource.endswith("/chat/sessions") and method == "GET":
        params = rest.query_params(event)
        limit = int(params["limit"]) if params.get("limit") else None
        result = service.list_sessions(caller, limit=limit, cursor=params.get("cursor"))
        return rest.json_response(200, result)

    if resource.endswith("/chat/sessions") and method == "DELETE":
        service.delete_history(caller)
        return rest.no_content()

    if resource.endswith("/chat/sessions/{sessionId}/ticket-draft") and method == "GET":
        session_id = rest.path_params(event).get("sessionId") or ""
        result = service.ticket_draft(caller, session_id)
        return rest.json_response(200, result)

    if resource.endswith("/chat/sessions/{sessionId}") and method == "GET":
        session_id = rest.path_params(event).get("sessionId") or ""
        result = service.get_session(caller, session_id)
        return rest.json_response(200, result)

    raise not_found("Unknown route.")


def handler(event: dict, context: object) -> dict:
    request_id = getattr(context, "aws_request_id", None)
    try:
        service = _build_service()
        return _route(event, service)
    except ApiError as exc:
        return rest.error_response(exc, request_id)
    except Exception:  # noqa: BLE001 — never leak internals or chat content to the client
        logger.exception("Unhandled error in chat handler")
        return rest.error_response(internal_error(), request_id)

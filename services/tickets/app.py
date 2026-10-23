"""Lambda entrypoint for the ``tickets`` function (handler = ``app.handler``).

Routes (infra/app contract, section 2): GET/POST /tickets, GET/PATCH
/tickets/{ticketId}. The native Cognito authorizer has already validated the
token; claims are in ``event.requestContext.authorizer.claims``.
"""

from __future__ import annotations

import logging
import os

import rest
from auth import caller_from_event
from errors import ApiError, internal_error, not_found
from service import TicketService

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# The SLA delay is configuration (RF01). Overridable in dev with a reduced value.
_SLA_SECONDS = int(os.environ.get("SLA_SECONDS", str(24 * 60 * 60)))


def _build_service() -> TicketService:
    # Imported lazily so unit tests never need boto3 or AWS configuration.
    from adapters import build_from_env

    store, alerts, scheduler = build_from_env()
    return TicketService(store, alerts, scheduler, sla_seconds=_SLA_SECONDS)


def _route(event: dict, service: TicketService) -> dict:
    method = (event.get("httpMethod") or "").upper()
    resource = event.get("resource") or event.get("path") or ""
    caller = caller_from_event(event)

    if resource.endswith("/tickets") and method == "POST":
        body = rest.parse_json_body(event)
        created = service.create(caller, body)
        location = f"/tickets/{created['id']}"
        return rest.json_response(201, created, {"Location": location})

    if resource.endswith("/tickets") and method == "GET":
        params = event.get("queryStringParameters") or {}
        sort = params.get("sort") or "createdAt:desc"
        ascending = sort == "createdAt:asc"
        limit = int(params.get("limit") or 20)
        page = service.list_tickets(
            caller,
            status=params.get("status"),
            category=params.get("category"),
            ascending=ascending,
            limit=limit,
            cursor=params.get("cursor"),
        )
        return rest.json_response(200, page)

    if resource.endswith("/tickets/{ticketId}") and method == "GET":
        ticket_id = (event.get("pathParameters") or {}).get("ticketId", "")
        detail = service.get_ticket(caller, ticket_id)
        return rest.json_response(200, detail)

    if resource.endswith("/tickets/{ticketId}") and method == "PATCH":
        ticket_id = (event.get("pathParameters") or {}).get("ticketId", "")
        body = rest.parse_json_body(event)
        detail = service.update(caller, ticket_id, body)
        return rest.json_response(200, detail)

    raise not_found("Unknown route.")


def handler(event: dict, context: object) -> dict:
    request_id = getattr(context, "aws_request_id", None)
    try:
        service = _build_service()
        return _route(event, service)
    except ApiError as exc:
        return rest.error_response(exc, request_id)
    except Exception:  # noqa: BLE001 — never leak internals or content to the client
        logger.exception("Unhandled error in tickets handler")
        return rest.error_response(internal_error(), request_id)

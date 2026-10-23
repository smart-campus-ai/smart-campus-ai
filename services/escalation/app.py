"""Lambda entrypoint for the ``escalation`` function (handler = ``app.handler``).

Invoked asynchronously once per ticket by the EventBridge Scheduler schedule that
``tickets`` created at ticket creation (ADR-0008). The payload carries only the
ticket id: ``{"ticketId": "<id>"}`` (no PII). The function is idempotent.
"""

from __future__ import annotations

import logging

from service import EscalationService

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _build_service() -> EscalationService:
    from adapters import build_from_env

    store, alerts = build_from_env()
    return EscalationService(store, alerts)


def handler(event: dict, context: object) -> dict:
    ticket_id = (event or {}).get("ticketId", "")
    service = _build_service()
    escalated = service.escalate(ticket_id)
    # Structured result for the logs; no ticket content.
    logger.info("escalation processed", extra={"ticketId": ticket_id, "escalated": escalated})
    return {"ticketId": ticket_id, "escalated": escalated}

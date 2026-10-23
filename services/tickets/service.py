"""Ticket use cases: create, list, get, update.

Pure orchestration over the ports; no AWS import here. A clock and an id factory
are injected so tests are deterministic (and so the same timestamp keys META,
the first EVENT and the SLA schedule).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Callable

import domain
import mapping
from auth import Caller, require_admin
from errors import not_found
from ports import AdminAlerts, SlaScheduler, TicketStore
from ulid import new_ulid

# RF01: the 24h delay is configuration, not a constant. Expressed in seconds so a
# reduced value can be used in dev. The handler passes it in from the environment.
DEFAULT_SLA_SECONDS = 24 * 60 * 60


def _now_iso(clock: Callable[[], datetime]) -> str:
    return clock().astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


class TicketService:
    def __init__(
        self,
        store: TicketStore,
        alerts: AdminAlerts,
        scheduler: SlaScheduler,
        *,
        sla_seconds: int = DEFAULT_SLA_SECONDS,
        clock: Callable[[], datetime] | None = None,
        id_factory: Callable[[], str] = new_ulid,
    ) -> None:
        self._store = store
        self._alerts = alerts
        self._scheduler = scheduler
        self._sla_seconds = sla_seconds
        self._clock = clock or (lambda: datetime.now(timezone.utc))
        self._id_factory = id_factory

    # --- US04: create -----------------------------------------------------

    def create(self, caller: Caller, body: object) -> dict:
        """Create a ticket owned by the caller and schedule the SLA escalation.

        Returns the created Ticket summary (contract 201 body). Enforces:
          - initial status "Ouvert" and owner = JWT sub (US04-AC4, RF01-AC1);
          - security category -> priority "critique" + immediate admin alert (US04-AC5);
          - a single SLA schedule at creation + 24h (RF01-AC2).
        """

        data = domain.validate_create_request(body)

        ticket_id = self._id_factory()
        now = self._clock().astimezone(timezone.utc)
        created_at = now.isoformat(timespec="milliseconds").replace("+00:00", "Z")
        category = data["category"]

        ticket = {
            "id": ticket_id,
            "title": data["title"],
            "description": data["description"],
            "category": category,
            "status": domain.STATUS_OUVERT,
            "priority": domain.initial_priority(category),
            "location": data.get("location"),
            "ownerSub": caller.sub,  # identity from the JWT, never the body
            "assigneeSub": None,
            "createdAt": created_at,
            "updatedAt": created_at,
        }

        meta_item = mapping.build_meta_item(ticket)
        creation_event = {
            "at": created_at,
            "actorSub": caller.sub,
            "field": "status",
            "oldValue": None,
            "newValue": domain.STATUS_OUVERT,
        }
        event_item = mapping.build_event_item(ticket_id, creation_event)

        self._store.put_ticket(meta_item, event_item)

        # RF01-AC2: one-time schedule at(created + sla) targeting escalation.
        fire_at = (now + timedelta(seconds=self._sla_seconds)).isoformat(
            timespec="seconds"
        ).replace("+00:00", "Z")
        self._scheduler.schedule_escalation(ticket_id, fire_at)

        # US04-AC5: security ticket -> immediate admin alert (no PII, no content).
        if category == domain.SECURITY_CATEGORY:
            self._alerts.publish(
                subject="New security ticket",
                message=f"A security ticket was created: {ticket_id}",
            )

        return mapping.meta_to_summary(meta_item)

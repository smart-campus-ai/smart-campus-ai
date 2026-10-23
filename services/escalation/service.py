"""Escalation use case (RF01), idempotent and side-effect-free when ineligible."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Callable

import domain
from ports import AdminAlerts, EscalationStore

# Marker attribute written on the META item when a ticket is escalated. Its absence
# is part of the idempotency condition (RF01-AC5).
ESCALATION_MARKER = "escalatedAt"


class EscalationService:
    def __init__(
        self,
        store: EscalationStore,
        alerts: AdminAlerts,
        *,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._store = store
        self._alerts = alerts
        self._clock = clock or (lambda: datetime.now(timezone.utc))

    def escalate(self, ticket_id: str) -> bool:
        """Escalate one ticket. Returns True if escalated, False on any no-op.

        No-op (no change, no alert) when:
          - the ticket does not exist;
          - it has left "Ouvert" before the SLA fired (RF01-AC4);
          - it was already escalated (RF01-AC5).
        The eligibility is re-checked atomically in the store (conditional write),
        so a race or a duplicate invocation cannot escalate twice.
        """

        if not ticket_id:
            return False

        meta = self._store.get_meta(ticket_id)
        if meta is None:
            return False
        if not domain.is_open(meta.get("status", "")):
            return False
        if meta.get(ESCALATION_MARKER):
            return False

        now = self._clock().astimezone(timezone.utc)
        at = now.isoformat(timespec="milliseconds").replace("+00:00", "Z")
        old_priority = meta.get("priority", domain.PRIORITY_NORMALE)
        new_priority = domain.escalated_priority(old_priority)

        event_item = {
            "pk": f"TICKET#{ticket_id}",
            "sk": f"EVENT#{at}#000",
            "at": at,
            "actorSub": "system:escalation",
            "field": "escalation",
            "oldValue": old_priority,
            "newValue": new_priority,
        }

        applied = self._store.escalate(ticket_id, new_priority, at, event_item)
        if not applied:
            # The conditional write lost the race: another actor changed the ticket
            # or it was already escalated. Idempotent no-op, no alert.
            return False

        # RF01-AC3: alert admins. No PII, no ticket content, only the id.
        self._alerts.publish(
            subject="SLA breach: ticket escalated",
            message=f"Ticket {ticket_id} was not taken in charge within the SLA and was escalated.",
        )
        return True

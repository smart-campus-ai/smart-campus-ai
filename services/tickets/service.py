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

    # --- US03: list and get ----------------------------------------------

    def list_tickets(
        self,
        caller: Caller,
        *,
        status: str | None = None,
        category: str | None = None,
        ascending: bool = False,
        limit: int = 20,
        cursor: str | None = None,
    ) -> dict:
        """List tickets visible to the caller (US03-AC1/AC4).

        A student sees only tickets they own (by-owner GSI, keyed by the JWT sub);
        an admin sees all (by-status GSI). The table is never scanned. Category is
        an optional post-filter on the page. Returns a contract TicketPage.
        """

        if status is not None:
            domain._require_enum(status, "status", domain.TICKET_STATUSES)  # noqa: SLF001
        if category is not None:
            domain._require_enum(category, "category", domain.TICKET_CATEGORIES)  # noqa: SLF001
        limit = max(1, min(int(limit), 100))

        if caller.is_admin:
            items, next_cursor = self._list_admin(status, ascending, limit, cursor)
        else:
            # BOLA: identity is the JWT sub; a student never reaches another owner.
            items, next_cursor = self._store.query_by_owner(
                caller.sub, status=status, ascending=ascending, limit=limit, cursor=cursor
            )

        summaries = [mapping.meta_to_summary(i) for i in items]
        if category is not None:
            summaries = [s for s in summaries if s["category"] == category]
        return {"items": summaries, "nextCursor": next_cursor}

    def _list_admin(self, status, ascending, limit, cursor):
        if status is not None:
            return self._store.query_by_status(
                status, ascending=ascending, limit=limit, cursor=cursor
            )
        # No status filter: union the by-status queries across every status, so the
        # admin "all" list still avoids a Scan. Cursor is not supported in this mode.
        collected: list[dict] = []
        for st in domain.TICKET_STATUSES:
            page, _ = self._store.query_by_status(
                st, ascending=ascending, limit=limit, cursor=None
            )
            collected.extend(page)
        collected.sort(key=lambda m: m["createdAt"], reverse=not ascending)
        return collected[:limit], None

    def get_ticket(self, caller: Caller, ticket_id: str) -> dict:
        """Return a ticket detail with history; 404 if hidden from the caller.

        A student requesting a ticket they do not own gets 404, never 403, so the
        existence of another student's ticket is never revealed (US03-AC5 / BOLA).
        Admins also see the immutable audit trail (US01-AC3).
        """

        meta, children = self._store.get_detail(ticket_id)
        if meta is None:
            raise not_found("Ticket not found.")
        if not caller.is_admin and meta["ownerSub"] != caller.sub:
            raise not_found("Ticket not found.")

        notes = [
            mapping.note_item_to_note(c)
            for c in children
            if c.get("sk", "").startswith(mapping.SK_NOTE_PREFIX)
        ]
        # A student only sees student-facing notes (US03-AC2).
        if not caller.is_admin:
            notes = [n for n in notes if n["audience"] == "student"]

        detail = {
            "id": meta["id"],
            "title": meta["title"],
            "description": meta["description"],
            "category": meta["category"],
            "status": meta["status"],
            "priority": meta["priority"],
            "ownerSub": meta["ownerSub"],
            "createdAt": meta["createdAt"],
            "updatedAt": meta["updatedAt"],
            "notes": notes,
            "attachments": [],
        }
        if meta.get("location") is not None:
            detail["location"] = meta["location"]
        if meta.get("assigneeSub") is not None:
            detail["assigneeSub"] = meta["assigneeSub"]

        if caller.is_admin:
            detail["history"] = [
                mapping.event_item_to_audit(c)
                for c in children
                if c.get("sk", "").startswith(mapping.SK_EVENT_PREFIX)
            ]

        return detail

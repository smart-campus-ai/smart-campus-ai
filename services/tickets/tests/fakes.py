"""In-memory fakes of the ports, so tests run fully offline (no AWS)."""

from __future__ import annotations

import mapping
from errors import conflict


class FakeStore:
    """In-memory TicketStore keyed by (pk, sk), mimicking the table shape."""

    def __init__(self) -> None:
        self.items: dict[tuple[str, str], dict] = {}

    def put_ticket(self, meta_item: dict, event_item: dict) -> None:
        key = (meta_item["pk"], meta_item["sk"])
        if key in self.items:
            raise conflict("Ticket already exists.")
        self.items[key] = dict(meta_item)
        self.items[(event_item["pk"], event_item["sk"])] = dict(event_item)

    def get_meta(self, ticket_id: str) -> dict | None:
        return self.items.get((mapping.ticket_pk(ticket_id), mapping.SK_META))

    def get_detail(self, ticket_id: str) -> tuple[dict | None, list[dict]]:
        pk = mapping.ticket_pk(ticket_id)
        meta = self.items.get((pk, mapping.SK_META))
        children = [
            dict(v)
            for (ipk, isk), v in sorted(self.items.items())
            if ipk == pk and isk != mapping.SK_META
        ]
        return (dict(meta) if meta else None, children)

    def _page(self, metas: list[dict], ascending: bool, limit: int, cursor: str | None):
        metas = sorted(metas, key=lambda m: m["createdAt"], reverse=not ascending)
        start = 0
        if cursor is not None:
            start = int(cursor)
        page = metas[start : start + limit]
        next_cursor = str(start + limit) if start + limit < len(metas) else None
        return page, next_cursor

    def query_by_owner(self, owner_sub, *, status, ascending, limit, cursor):
        metas = [
            dict(v)
            for (pk, sk), v in self.items.items()
            if sk == mapping.SK_META and v["ownerSub"] == owner_sub
        ]
        if status is not None:
            metas = [m for m in metas if m["status"] == status]
        return self._page(metas, ascending, limit, cursor)

    def query_by_status(self, status, *, ascending, limit, cursor):
        metas = [dict(v) for (pk, sk), v in self.items.items() if sk == mapping.SK_META]
        if status is not None:
            metas = [m for m in metas if m["status"] == status]
        return self._page(metas, ascending, limit, cursor)

    def apply_update(self, ticket_id, updated_meta, event_items):
        self.items[(updated_meta["pk"], updated_meta["sk"])] = dict(updated_meta)
        for ev in event_items:
            self.items[(ev["pk"], ev["sk"])] = dict(ev)


class FakeAlerts:
    def __init__(self) -> None:
        self.published: list[tuple[str, str]] = []

    def publish(self, subject: str, message: str) -> None:
        self.published.append((subject, message))


class FakeScheduler:
    def __init__(self) -> None:
        self.schedules: dict[str, str] = {}

    def schedule_escalation(self, ticket_id: str, fire_at_iso_utc: str) -> None:
        # A single schedule per ticket: the name is derived from the id (idempotent).
        self.schedules[ticket_id] = fire_at_iso_utc

"""In-memory fakes for the escalation ports (offline tests)."""

from __future__ import annotations

from service import ESCALATION_MARKER


class FakeStore:
    def __init__(self, meta: dict | None = None) -> None:
        self.meta = dict(meta) if meta else None
        self.events: list[dict] = []
        self.escalate_calls = 0

    def get_meta(self, ticket_id: str) -> dict | None:
        return dict(self.meta) if self.meta else None

    def escalate(self, ticket_id, new_priority, escalated_at, event_item) -> bool:
        self.escalate_calls += 1
        # Re-check the condition atomically, like the DynamoDB conditional write.
        if self.meta is None:
            return False
        if self.meta.get("status") != "Ouvert":
            return False
        if self.meta.get(ESCALATION_MARKER):
            return False
        self.meta["priority"] = new_priority
        self.meta[ESCALATION_MARKER] = escalated_at
        self.meta["updatedAt"] = escalated_at
        self.events.append(dict(event_item))
        return True


class FakeAlerts:
    def __init__(self) -> None:
        self.published: list[tuple[str, str]] = []

    def publish(self, subject: str, message: str) -> None:
        self.published.append((subject, message))


def meta(**overrides) -> dict:
    base = {
        "pk": "TICKET#T1",
        "sk": "META",
        "id": "T1",
        "status": "Ouvert",
        "priority": "normale",
        "ownerSub": "student-A",
        "createdAt": "2026-10-23T08:00:00.000Z",
        "updatedAt": "2026-10-23T08:00:00.000Z",
    }
    base.update(overrides)
    return base

"""Ports for the escalation function, so the logic is testable offline."""

from __future__ import annotations

from typing import Protocol


class EscalationStore(Protocol):
    """Access to the tickets table for the escalation flow."""

    def get_meta(self, ticket_id: str) -> dict | None:
        """Return the META item of a ticket, or None if it does not exist."""

    def escalate(self, ticket_id: str, new_priority: str, escalated_at: str, event_item: dict) -> bool:
        """Atomically escalate a ticket if still eligible.

        Must apply a conditional write: only when status is still "Ouvert" AND the
        ticket has not been escalated yet (no escalation marker). Returns True if the
        escalation was applied, False if the condition failed (idempotent no-op).
        Appends the immutable escalation EVENT in the same transaction.
        """


class AdminAlerts(Protocol):
    """Publishes the escalation alert to admins (SNS). No PII, no ticket content."""

    def publish(self, subject: str, message: str) -> None: ...

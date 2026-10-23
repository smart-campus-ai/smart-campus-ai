"""Ports: the interfaces the handlers depend on, so the logic is testable offline.

Concrete AWS-backed adapters live in ``adapters.py`` and are only imported at
runtime (inside the Lambda). Tests inject in-memory fakes implementing these
Protocols, so no test ever touches AWS (infra/app contract, section 6).
"""

from __future__ import annotations

from typing import Protocol


class TicketStore(Protocol):
    """Persistence for the tickets table (DynamoDB). Never performs a Scan."""

    def put_ticket(self, meta_item: dict, event_item: dict) -> None:
        """Atomically create a ticket META item and its first EVENT item.

        Must fail if the ticket already exists (conditional write on pk/sk).
        """

    def get_meta(self, ticket_id: str) -> dict | None:
        """Return the META item of a ticket, or None if it does not exist."""

    def get_detail(self, ticket_id: str) -> tuple[dict | None, list[dict]]:
        """Return (META item, [item...]) for a ticket: META plus its EVENT/NOTE items."""

    def query_by_owner(
        self, owner_sub: str, *, status: str | None, ascending: bool, limit: int, cursor: str | None
    ) -> tuple[list[dict], str | None]:
        """Query the by-owner GSI. Returns (meta_items, next_cursor)."""

    def query_by_status(
        self, status: str | None, *, ascending: bool, limit: int, cursor: str | None
    ) -> tuple[list[dict], str | None]:
        """Query the by-status GSI (admin list). Returns (meta_items, next_cursor)."""

    def apply_update(self, ticket_id: str, updated_meta: dict, event_items: list[dict]) -> None:
        """Persist an updated META item and append immutable EVENT items."""


class AdminAlerts(Protocol):
    """Publishes admin alerts (SNS). Payload carries no PII or ticket content."""

    def publish(self, subject: str, message: str) -> None: ...


class SlaScheduler(Protocol):
    """Creates the one-time SLA escalation schedule for a ticket (RF01, ADR-0008)."""

    def schedule_escalation(self, ticket_id: str, fire_at_iso_utc: str) -> None: ...

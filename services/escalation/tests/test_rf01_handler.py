"""RF01 at the handler level: Scheduler payload in, idempotent result out."""

from __future__ import annotations

from datetime import datetime, timezone

import app
import pytest
from fakes import FakeAlerts, FakeStore, meta
from service import EscalationService


@pytest.fixture
def wired(monkeypatch):
    store = FakeStore(meta(status="Ouvert", priority="normale"))
    alerts = FakeAlerts()
    service = EscalationService(
        store, alerts, clock=lambda: datetime(2026, 10, 24, 8, 0, 0, tzinfo=timezone.utc)
    )
    monkeypatch.setattr(app, "_build_service", lambda: service)
    return store, alerts


def test_RF01_AC3_handler_escalates_on_scheduler_payload(wired):
    store, alerts = wired
    result = app.handler({"ticketId": "T1"}, None)
    assert result == {"ticketId": "T1", "escalated": True}
    assert len(alerts.published) == 1


def test_RF01_AC5_handler_second_call_is_noop(wired):
    app.handler({"ticketId": "T1"}, None)
    result = app.handler({"ticketId": "T1"}, None)
    assert result == {"ticketId": "T1", "escalated": False}

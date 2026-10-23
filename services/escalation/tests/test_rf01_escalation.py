"""RF01 — Cycle de vie et SLA (escalation side). Tests named after the ACs."""

from __future__ import annotations

from datetime import datetime, timezone

import domain
from fakes import FakeAlerts, FakeStore, meta
from service import ESCALATION_MARKER, EscalationService

FIXED_NOW = datetime(2026, 10, 24, 8, 0, 0, tzinfo=timezone.utc)


def make_service(store):
    alerts = FakeAlerts()
    service = EscalationService(store, alerts, clock=lambda: FIXED_NOW)
    return service, alerts


def test_RF01_AC3_open_ticket_is_escalated_priority_raised_and_admins_alerted():
    store = FakeStore(meta(status="Ouvert", priority="normale"))
    service, alerts = make_service(store)

    assert service.escalate("T1") is True
    assert store.meta["priority"] == domain.escalated_priority("normale")  # normale -> haute
    assert store.meta[ESCALATION_MARKER] == "2026-10-24T08:00:00.000Z"
    assert len(alerts.published) == 1
    subject, message = alerts.published[0]
    assert "escalated" in subject.lower()
    assert "T1" in message


def test_RF01_AC3_audit_event_records_the_escalation():
    store = FakeStore(meta(status="Ouvert", priority="haute"))
    service, _ = make_service(store)
    service.escalate("T1")
    assert len(store.events) == 1
    ev = store.events[0]
    assert ev["field"] == "escalation"
    assert ev["oldValue"] == "haute"
    assert ev["newValue"] == "critique"
    assert ev["actorSub"] == "system:escalation"


def test_RF01_AC4_ticket_taken_in_charge_is_not_escalated():
    store = FakeStore(meta(status="En cours"))
    service, alerts = make_service(store)

    assert service.escalate("T1") is False
    assert store.meta.get(ESCALATION_MARKER) is None
    assert alerts.published == []


def test_RF01_AC5_second_invocation_is_a_noop():
    store = FakeStore(meta(status="Ouvert", priority="normale"))
    service, alerts = make_service(store)

    assert service.escalate("T1") is True
    # Second invocation for the same ticket: already escalated -> no change, no alert.
    assert service.escalate("T1") is False
    assert len(alerts.published) == 1
    assert store.meta["priority"] == domain.escalated_priority("normale")


def test_RF01_unknown_ticket_is_a_noop():
    store = FakeStore(None)
    service, alerts = make_service(store)
    assert service.escalate("missing") is False
    assert alerts.published == []


def test_RF01_critique_stays_critique_on_escalation():
    store = FakeStore(meta(status="Ouvert", priority="critique"))
    service, _ = make_service(store)
    service.escalate("T1")
    assert store.meta["priority"] == "critique"


def test_RF01_empty_payload_is_a_noop():
    store = FakeStore(meta(status="Ouvert"))
    service, alerts = make_service(store)
    assert service.escalate("") is False
    assert store.escalate_calls == 0
    assert alerts.published == []

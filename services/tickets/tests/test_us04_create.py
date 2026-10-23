"""US04 — Création d'un ticket par l'étudiant. Tests named after the ACs."""

from __future__ import annotations

from datetime import datetime, timezone

import domain
import pytest
from auth import Caller
from errors import ApiError
from fakes import FakeAlerts, FakeScheduler, FakeStore
from service import TicketService

FIXED_NOW = datetime(2026, 10, 23, 8, 0, 0, tzinfo=timezone.utc)


def make_service(**kwargs):
    store = FakeStore()
    alerts = FakeAlerts()
    scheduler = FakeScheduler()
    seq = iter([f"{i:026d}".replace("0", "A") for i in range(1, 50)])
    service = TicketService(
        store,
        alerts,
        scheduler,
        clock=lambda: FIXED_NOW,
        id_factory=lambda: next(seq),
        **kwargs,
    )
    return service, store, alerts, scheduler


STUDENT = Caller(sub="student-sub-1", groups=("student",))


def valid_body(**overrides):
    body = {"title": "Wifi down", "category": "incident", "description": "No connection in B12"}
    body.update(overrides)
    return body


def test_US04_AC2_fields_are_persisted():
    service, store, _, _ = make_service()
    summary = service.create(STUDENT, valid_body(location="Building B12"))

    meta = store.get_meta(summary["id"])
    assert meta["title"] == "Wifi down"
    assert meta["category"] == "incident"
    assert meta["description"] == "No connection in B12"
    assert meta["location"] == "Building B12"


def test_US04_AC3_invalid_payload_is_rejected_400():
    service, _, _, _ = make_service()
    with pytest.raises(ApiError) as exc:
        service.create(STUDENT, {"title": "", "category": "incident", "description": "x"})
    assert exc.value.status_code == 400
    assert exc.value.code == "validation_error"


def test_US04_AC3_unknown_category_is_rejected_400():
    service, _, _, _ = make_service()
    with pytest.raises(ApiError) as exc:
        service.create(STUDENT, valid_body(category="autre"))
    assert exc.value.status_code == 400


def test_US04_AC4_unique_id_initial_status_open_and_owner_is_jwt_sub():
    service, store, _, _ = make_service()
    summary = service.create(STUDENT, valid_body())

    assert summary["id"]  # a unique id was assigned
    assert summary["status"] == domain.STATUS_OUVERT
    assert summary["ownerSub"] == STUDENT.sub
    meta = store.get_meta(summary["id"])
    assert meta["ownerSub"] == STUDENT.sub


def test_US04_AC4_owner_in_body_is_ignored():
    service, store, _, _ = make_service()
    summary = service.create(STUDENT, valid_body(ownerSub="attacker", id="forged"))
    # additionalProperties are rejected by validation, so forging is blocked at 400.
    # (validate_create_request only keeps title/category/description/location)
    meta = store.get_meta(summary["id"])
    assert meta["ownerSub"] == STUDENT.sub
    assert meta["id"] != "forged"


def test_US04_AC4_single_sla_schedule_created():
    service, _, _, scheduler = make_service()
    summary = service.create(STUDENT, valid_body())
    assert list(scheduler.schedules) == [summary["id"]]
    # at(created + 24h), in UTC
    assert scheduler.schedules[summary["id"]] == "2026-10-24T08:00:00Z"


def test_US04_AC5_security_category_sets_critique_and_alerts_admins():
    service, store, alerts, _ = make_service()
    summary = service.create(STUDENT, valid_body(category="sécurité"))

    assert summary["priority"] == domain.PRIORITY_CRITIQUE
    assert store.get_meta(summary["id"])["priority"] == domain.PRIORITY_CRITIQUE
    assert len(alerts.published) == 1
    subject, message = alerts.published[0]
    assert "security" in subject.lower()
    # No ticket content leaks into the alert (only the id).
    assert "No connection" not in message


def test_US04_non_security_has_normal_priority_and_no_alert():
    service, _, alerts, _ = make_service()
    summary = service.create(STUDENT, valid_body(category="besoin"))
    assert summary["priority"] == domain.PRIORITY_NORMALE
    assert alerts.published == []


def test_US04_AC4_first_audit_event_records_open():
    service, store, _, _ = make_service()
    summary = service.create(STUDENT, valid_body())
    _, children = store.get_detail(summary["id"])
    events = [c for c in children if c["sk"].startswith("EVENT#")]
    assert len(events) == 1
    assert events[0]["field"] == "status"
    assert events[0]["oldValue"] is None
    assert events[0]["newValue"] == domain.STATUS_OUVERT


def test_US04_configurable_sla_delay():
    service, _, _, scheduler = make_service(sla_seconds=60)
    summary = service.create(STUDENT, valid_body())
    assert scheduler.schedules[summary["id"]] == "2026-10-23T08:01:00Z"

"""US01 — Gestion et mise à jour des tickets par l'administrateur. Tests per AC."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import domain
import pytest
from auth import Caller
from errors import ApiError
from fakes import FakeAlerts, FakeScheduler, FakeStore
from service import TicketService

ADMIN = Caller(sub="admin-1", groups=("admin",))
STUDENT = Caller(sub="student-A", groups=("student",))


def make_service():
    store, alerts, scheduler = FakeStore(), FakeAlerts(), FakeScheduler()
    counter = {"n": 0}
    base = datetime(2026, 10, 23, 8, 0, 0, tzinfo=timezone.utc)

    def clock():
        counter["n"] += 1
        return base + timedelta(minutes=counter["n"])

    seq = iter([chr(65 + (i % 26)) * 26 for i in range(1, 99)])
    service = TicketService(store, alerts, scheduler, clock=clock, id_factory=lambda: next(seq))
    return service, store


def new_ticket(service, owner=STUDENT, **overrides):
    body = {"title": "t", "category": "incident", "description": "d"}
    body.update(overrides)
    return service.create(owner, body)


def test_US01_AC2_update_status_assignee_priority_and_note():
    service, _ = make_service()
    created = new_ticket(service)
    detail = service.update(
        ADMIN,
        created["id"],
        {
            "status": domain.STATUS_EN_COURS,
            "assigneeSub": "operator-7",
            "priority": domain.PRIORITY_HAUTE,
            "note": {"body": "on it", "audience": "internal"},
        },
    )
    assert detail["status"] == domain.STATUS_EN_COURS
    assert detail["assigneeSub"] == "operator-7"
    assert detail["priority"] == domain.PRIORITY_HAUTE
    assert detail["status"] in domain.TICKET_STATUSES
    assert detail["priority"] in domain.TICKET_PRIORITIES


def test_US01_AC3_audit_event_per_changed_field_with_actor_and_values():
    service, _ = make_service()
    created = new_ticket(service)
    detail = service.update(
        ADMIN,
        created["id"],
        {"status": domain.STATUS_EN_COURS, "priority": domain.PRIORITY_HAUTE},
    )
    # creation event + status change + priority change
    history = detail["history"]
    fields = [h["field"] for h in history]
    assert fields.count("status") == 2  # creation + change
    assert "priority" in fields
    status_change = [h for h in history if h["field"] == "status" and h["oldValue"] is not None][0]
    assert status_change["actorSub"] == ADMIN.sub
    assert status_change["oldValue"] == domain.STATUS_OUVERT
    assert status_change["newValue"] == domain.STATUS_EN_COURS


def test_US01_AC3_audit_note_event_carries_no_content():
    service, _ = make_service()
    created = new_ticket(service)
    detail = service.update(
        ADMIN, created["id"], {"note": {"body": "sensitive content", "audience": "student"}}
    )
    note_events = [h for h in detail["history"] if h["field"] == "note"]
    assert len(note_events) == 1
    # Only the audience is recorded, never the body.
    assert note_events[0]["newValue"] == "student"
    assert "sensitive" not in str(note_events[0])


def test_US01_AC5_terminal_status_without_resolution_note_is_rejected_400():
    service, store = make_service()
    created = new_ticket(service)
    for target in (domain.STATUS_RESOLU, domain.STATUS_FERME):
        with pytest.raises(ApiError) as exc:
            service.update(ADMIN, created["id"], {"status": target})
        assert exc.value.status_code == 400
        # status unchanged
        assert store.get_meta(created["id"])["status"] == domain.STATUS_OUVERT


def test_US01_AC5_terminal_status_with_student_note_succeeds():
    service, _ = make_service()
    created = new_ticket(service)
    detail = service.update(
        ADMIN,
        created["id"],
        {"status": domain.STATUS_RESOLU, "note": {"body": "fixed", "audience": "student"}},
    )
    assert detail["status"] == domain.STATUS_RESOLU


def test_US01_AC5_internal_note_does_not_satisfy_resolution_requirement():
    service, _ = make_service()
    created = new_ticket(service)
    with pytest.raises(ApiError) as exc:
        service.update(
            ADMIN,
            created["id"],
            {"status": domain.STATUS_FERME, "note": {"body": "x", "audience": "internal"}},
        )
    assert exc.value.status_code == 400


def test_US01_AC6_student_calling_update_is_forbidden_403():
    service, _ = make_service()
    created = new_ticket(service)
    with pytest.raises(ApiError) as exc:
        service.update(STUDENT, created["id"], {"status": domain.STATUS_EN_COURS})
    assert exc.value.status_code == 403
    assert exc.value.code == "forbidden"


def test_US01_AC4_student_sees_new_status_and_student_note():
    service, _ = make_service()
    created = new_ticket(service)
    service.update(
        ADMIN,
        created["id"],
        {"status": domain.STATUS_EN_COURS, "note": {"body": "hello", "audience": "student"}},
    )
    detail = service.get_ticket(STUDENT, created["id"])
    assert detail["status"] == domain.STATUS_EN_COURS
    assert [n["audience"] for n in detail["notes"]] == ["student"]


def test_US01_update_unknown_ticket_returns_404():
    service, _ = make_service()
    with pytest.raises(ApiError) as exc:
        service.update(ADMIN, "Z" * 26, {"status": domain.STATUS_EN_COURS})
    assert exc.value.status_code == 404


def test_US01_empty_update_is_rejected_400():
    service, _ = make_service()
    created = new_ticket(service)
    with pytest.raises(ApiError) as exc:
        service.update(ADMIN, created["id"], {})
    assert exc.value.status_code == 400

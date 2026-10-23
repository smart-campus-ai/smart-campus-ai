"""US03 — Suivi de l'état d'avancement des tickets. Tests named after the ACs."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import domain
import pytest
from auth import Caller
from errors import ApiError
from fakes import FakeAlerts, FakeScheduler, FakeStore
from service import TicketService

STUDENT_A = Caller(sub="student-A", groups=("student",))
STUDENT_B = Caller(sub="student-B", groups=("student",))
ADMIN = Caller(sub="admin-1", groups=("admin",))


def make_service():
    store, alerts, scheduler = FakeStore(), FakeAlerts(), FakeScheduler()
    counter = {"n": 0}
    base = datetime(2026, 10, 23, 8, 0, 0, tzinfo=timezone.utc)

    def clock():
        counter["n"] += 1
        return base + timedelta(minutes=counter["n"])

    seq = iter([f"{i:026d}".replace("0", "A") for i in range(1, 99)])
    service = TicketService(
        store, alerts, scheduler, clock=clock, id_factory=lambda: next(seq)
    )
    return service, store


def create(service, caller, **overrides):
    body = {"title": "t", "category": "incident", "description": "d"}
    body.update(overrides)
    return service.create(caller, body)


def test_US03_AC1_list_returns_owner_tickets_with_status_and_updated_at():
    service, _ = make_service()
    created = create(service, STUDENT_A)
    page = service.list_tickets(STUDENT_A)
    assert len(page["items"]) == 1
    item = page["items"][0]
    assert item["id"] == created["id"]
    assert item["status"] == domain.STATUS_OUVERT
    assert "updatedAt" in item


def _add_note(store, ticket_id, *, body, audience, created_at):
    from mapping import build_note_item

    note = build_note_item(
        ticket_id,
        {
            "id": "A" * 26,
            "body": body,
            "audience": audience,
            "authorRole": "admin",
            "createdAt": created_at,
        },
    )
    store.items[(note["pk"], note["sk"])] = note


def test_US03_AC2_detail_includes_student_notes_only():
    service, store = make_service()
    created = create(service, STUDENT_A)
    tid = created["id"]
    _add_note(store, tid, body="visible", audience="student", created_at="2026-10-23T09:00:00.000Z")
    _add_note(store, tid, body="secret", audience="internal", created_at="2026-10-23T09:01:00.000Z")

    detail = service.get_ticket(STUDENT_A, tid)
    audiences = {n["audience"] for n in detail["notes"]}
    assert audiences == {"student"}
    # A student never gets the audit history.
    assert "history" not in detail


def test_US03_AC3_status_is_one_of_the_reference_values():
    service, _ = make_service()
    created = create(service, STUDENT_A)
    assert created["status"] in domain.TICKET_STATUSES


def test_US03_AC4_filter_by_status_and_sort():
    service, store = make_service()
    t1 = create(service, STUDENT_A)
    t2 = create(service, STUDENT_A)
    # Move t2 to "En cours" in the store.
    meta = store.get_meta(t2["id"])
    meta["status"] = domain.STATUS_EN_COURS
    store.apply_update(t2["id"], meta, [])

    page = service.list_tickets(STUDENT_A, status=domain.STATUS_EN_COURS)
    assert [i["id"] for i in page["items"]] == [t2["id"]]

    # Ascending sort returns the oldest first.
    page_asc = service.list_tickets(STUDENT_A, ascending=True)
    ids = [i["id"] for i in page_asc["items"]]
    assert ids == [t1["id"], t2["id"]]


def test_US03_AC5_bola_get_other_students_ticket_returns_404():
    service, _ = make_service()
    created = create(service, STUDENT_B)  # owned by B
    with pytest.raises(ApiError) as exc:
        service.get_ticket(STUDENT_A, created["id"])  # A requests it
    assert exc.value.status_code == 404
    assert exc.value.code == "not_found"


def test_US03_AC5_bola_list_never_contains_other_students_ticket():
    service, _ = make_service()
    create(service, STUDENT_B)
    create(service, STUDENT_A)
    page = service.list_tickets(STUDENT_A)
    owners = {i["ownerSub"] for i in page["items"]}
    assert owners == {"student-A"}


def test_US03_unknown_ticket_returns_404():
    service, _ = make_service()
    with pytest.raises(ApiError) as exc:
        service.get_ticket(STUDENT_A, "Z" * 26)
    assert exc.value.status_code == 404


def test_US03_admin_sees_all_tickets_and_history():
    service, _ = make_service()
    a = create(service, STUDENT_A)
    create(service, STUDENT_B)
    page = service.list_tickets(ADMIN)
    assert len(page["items"]) == 2
    detail = service.get_ticket(ADMIN, a["id"])
    assert "history" in detail
    assert len(detail["history"]) == 1  # the creation event

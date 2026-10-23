"""US01 at the handler level: PATCH through app.handler."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

import app
import domain
import pytest
from auth import Caller
from fakes import FakeAlerts, FakeScheduler, FakeStore
from service import TicketService


@pytest.fixture
def wired(monkeypatch):
    store, alerts, scheduler = FakeStore(), FakeAlerts(), FakeScheduler()
    counter = {"n": 0}
    base = datetime(2026, 10, 23, 8, 0, 0, tzinfo=timezone.utc)

    def clock():
        counter["n"] += 1
        return base + timedelta(minutes=counter["n"])

    seq = iter([chr(65 + (i % 26)) * 26 for i in range(1, 99)])
    service = TicketService(store, alerts, scheduler, clock=clock, id_factory=lambda: next(seq))
    monkeypatch.setattr(app, "_build_service", lambda: service)
    return service


def ev(sub, groups, ticket_id, body):
    return {
        "httpMethod": "PATCH",
        "resource": "/tickets/{ticketId}",
        "pathParameters": {"ticketId": ticket_id},
        "requestContext": {"authorizer": {"claims": {"sub": sub, "cognito:groups": groups}}},
        "body": json.dumps(body),
    }


def _create(service):
    return service.create(Caller(sub="student-A", groups=("student",)), {"title": "t", "category": "incident", "description": "d"})


def test_US01_AC2_patch_returns_200_with_updated_detail(wired):
    created = _create(wired)
    resp = app.handler(ev("admin-1", "admin", created["id"], {"status": domain.STATUS_EN_COURS}), None)
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"])["status"] == domain.STATUS_EN_COURS


def test_US01_AC6_student_patch_returns_403(wired):
    created = _create(wired)
    resp = app.handler(ev("student-A", "student", created["id"], {"status": domain.STATUS_EN_COURS}), None)
    assert resp["statusCode"] == 403
    assert json.loads(resp["body"])["code"] == "forbidden"


def test_US01_AC5_terminal_without_note_returns_400(wired):
    created = _create(wired)
    resp = app.handler(ev("admin-1", "admin", created["id"], {"status": domain.STATUS_RESOLU}), None)
    assert resp["statusCode"] == 400
    assert json.loads(resp["body"])["code"] == "validation_error"

"""US03 at the handler level: list and get through app.handler, including BOLA."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

import app
import pytest
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

    seq = iter([f"{i:026d}".replace("0", "A") for i in range(1, 99)])
    service = TicketService(store, alerts, scheduler, clock=clock, id_factory=lambda: next(seq))
    monkeypatch.setattr(app, "_build_service", lambda: service)
    return service


def ev(method, resource, *, sub, groups="student", path_params=None, query=None, body=None):
    return {
        "httpMethod": method,
        "resource": resource,
        "pathParameters": path_params,
        "queryStringParameters": query,
        "requestContext": {"authorizer": {"claims": {"sub": sub, "cognito:groups": groups}}},
        "body": json.dumps(body) if body is not None else None,
    }


def _create(service, sub):
    from auth import Caller

    return service.create(Caller(sub=sub, groups=("student",)), {"title": "t", "category": "incident", "description": "d"})


def test_US03_AC1_get_list_returns_200_page(wired):
    _create(wired, "student-A")
    resp = app.handler(ev("GET", "/tickets", sub="student-A"), None)
    assert resp["statusCode"] == 200
    page = json.loads(resp["body"])
    assert len(page["items"]) == 1
    assert "nextCursor" in page


def test_US03_AC2_get_detail_returns_200(wired):
    created = _create(wired, "student-A")
    resp = app.handler(
        ev("GET", "/tickets/{ticketId}", sub="student-A", path_params={"ticketId": created["id"]}),
        None,
    )
    assert resp["statusCode"] == 200
    assert json.loads(resp["body"])["id"] == created["id"]


def test_US03_AC5_bola_get_returns_404_via_handler(wired):
    created = _create(wired, "student-B")
    resp = app.handler(
        ev("GET", "/tickets/{ticketId}", sub="student-A", path_params={"ticketId": created["id"]}),
        None,
    )
    assert resp["statusCode"] == 404
    assert json.loads(resp["body"])["code"] == "not_found"

"""US04 at the handler level: REST proxy in, {statusCode, headers, body} out."""

from __future__ import annotations

import json
from datetime import datetime, timezone

import app
import pytest
from fakes import FakeAlerts, FakeScheduler, FakeStore
from service import TicketService


@pytest.fixture
def wired(monkeypatch):
    store, alerts, scheduler = FakeStore(), FakeAlerts(), FakeScheduler()
    seq = iter([f"{i:026d}".replace("0", "A") for i in range(1, 50)])
    service = TicketService(
        store,
        alerts,
        scheduler,
        clock=lambda: datetime(2026, 10, 23, 8, 0, 0, tzinfo=timezone.utc),
        id_factory=lambda: next(seq),
    )
    monkeypatch.setattr(app, "_build_service", lambda: service)
    return store, alerts, scheduler


def event(method, resource, *, claims=None, body=None):
    return {
        "httpMethod": method,
        "resource": resource,
        "requestContext": {"authorizer": {"claims": claims or {}}},
        "body": json.dumps(body) if body is not None else None,
    }


STUDENT_CLAIMS = {"sub": "student-1", "cognito:groups": "student"}


def test_US04_AC4_post_returns_201_with_location_and_body(wired):
    resp = app.handler(
        event(
            "POST",
            "/tickets",
            claims=STUDENT_CLAIMS,
            body={"title": "Wifi", "category": "incident", "description": "down"},
        ),
        None,
    )
    assert resp["statusCode"] == 201
    created = json.loads(resp["body"])
    assert resp["headers"]["Location"] == f"/tickets/{created['id']}"
    assert created["status"] == "Ouvert"
    assert created["ownerSub"] == "student-1"


def test_US04_AC3_invalid_body_returns_400(wired):
    resp = app.handler(
        event("POST", "/tickets", claims=STUDENT_CLAIMS, body={"title": ""}),
        None,
    )
    assert resp["statusCode"] == 400
    assert json.loads(resp["body"])["code"] == "validation_error"


def test_EN32_AC2_missing_token_returns_401(wired):
    resp = app.handler(
        event("POST", "/tickets", claims={}, body={"title": "x", "category": "incident", "description": "y"}),
        None,
    )
    assert resp["statusCode"] == 401
    assert json.loads(resp["body"])["code"] == "unauthorized"

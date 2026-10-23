"""US10 — Escalade d'une conversation chat vers un ticket (offline).

Named after the acceptance criteria of issue #16. AC1 (accessible button,
highlighted on "je ne sais pas") is a frontend concern (EN-85); the backend
criteria are the prefill and the caller scoping, plus the fact that creation
still flows through the unchanged US04 endpoint (AC3, verified by the tickets
service tests).
"""

from __future__ import annotations

import json
from datetime import datetime, timezone

import app
import domain
import pytest
from auth import Caller
from errors import ApiError
from fakes import FakeAssistant, FakeKnowledgeBase, FakeMetrics, FakeStore
from ports import Generation
from service import ChatService

STUDENT_A = Caller(sub="student-A", groups=("student",))
STUDENT_B = Caller(sub="student-B", groups=("student",))


def _service(store=None):
    seq = iter(f"{i:026d}".replace("0", "A") for i in range(1, 100))
    return ChatService(
        store or FakeStore(),
        FakeKnowledgeBase([]),
        FakeAssistant(Generation(text="", grounding=0.0, relevance=0.0, sources=())),
        thresholds=domain.Thresholds(0.7, 0.7),
        metrics=FakeMetrics(),
        clock=lambda: datetime(2026, 10, 23, 8, 0, 0, tzinfo=timezone.utc),
        id_factory=lambda: next(seq),
    )


def _seed_session(store, owner, sid, user_msgs):
    messages = []
    for i, text in enumerate(user_msgs):
        messages.append({"id": f"U{i}", "role": "user", "content": text, "createdAt": "2026-10-23T08:00:00Z"})
        messages.append({"id": f"A{i}", "role": "assistant", "content": domain.FALLBACK_REPLY, "createdAt": "2026-10-23T08:00:01Z"})
    store.sessions[sid] = {
        "id": sid, "ownerSub": owner, "messages": messages,
        "createdAt": "2026-10-23T08:00:00Z", "updatedAt": "2026-10-23T08:00:02Z",
    }


def test_US10_AC2_draft_is_prefilled_from_session_context():
    store = FakeStore()
    _seed_session(store, "student-A", "S1", ["Le wifi ne marche pas en D204", "toujours rien après reboot"])
    draft = _service(store).ticket_draft(STUDENT_A, "S1")
    # Title from the first question, description aggregates the student's turns.
    assert draft["title"] == "Le wifi ne marche pas en D204"
    assert "toujours rien après reboot" in draft["description"]
    assert "Le wifi ne marche pas en D204" in draft["description"]


def test_US10_AC2_draft_fields_respect_contract_limits():
    store = FakeStore()
    _seed_session(store, "student-A", "S1", ["x" * 500])
    draft = _service(store).ticket_draft(STUDENT_A, "S1")
    assert len(draft["title"]) <= 140
    assert len(draft["description"]) <= 5000


def test_US10_AC4_draft_uses_only_the_callers_own_session():
    store = FakeStore()
    _seed_session(store, "student-B", "S-B", ["problème de B"])
    # A cannot derive a draft from B's session: 404, no data leak.
    with pytest.raises(ApiError) as exc:
        _service(store).ticket_draft(STUDENT_A, "S-B")
    assert exc.value.status_code == 404


def test_US10_AC2_handler_returns_draft(monkeypatch):
    store = FakeStore()
    _seed_session(store, "student-1", "S1", ["imprimante HS au 2e"])
    svc = _service(store)
    monkeypatch.setattr(app, "_build_service", lambda: svc)
    event = {
        "httpMethod": "GET",
        "resource": "/chat/sessions/{sessionId}/ticket-draft",
        "pathParameters": {"sessionId": "S1"},
        "requestContext": {"authorizer": {"claims": {"sub": "student-1", "cognito:groups": "student"}}},
        "body": None,
    }
    resp = app.handler(event, None)
    assert resp["statusCode"] == 200
    draft = json.loads(resp["body"])
    assert draft["title"] == "imprimante HS au 2e"
    assert draft["description"]


def test_US10_AC4_handler_other_owner_returns_404(monkeypatch):
    store = FakeStore()
    _seed_session(store, "other", "S1", ["secret de other"])
    svc = _service(store)
    monkeypatch.setattr(app, "_build_service", lambda: svc)
    event = {
        "httpMethod": "GET",
        "resource": "/chat/sessions/{sessionId}/ticket-draft",
        "pathParameters": {"sessionId": "S1"},
        "requestContext": {"authorizer": {"claims": {"sub": "student-1", "cognito:groups": "student"}}},
        "body": None,
    }
    resp = app.handler(event, None)
    assert resp["statusCode"] == 404


def test_US10_empty_session_yields_safe_default_draft():
    store = FakeStore()
    store.sessions["S0"] = {
        "id": "S0", "ownerSub": "student-A", "messages": [],
        "createdAt": "2026-10-23T08:00:00Z", "updatedAt": "2026-10-23T08:00:00Z",
    }
    draft = _service(store).ticket_draft(STUDENT_A, "S0")
    assert draft["title"] == "Demande d'assistance"
    assert draft["description"] == ""

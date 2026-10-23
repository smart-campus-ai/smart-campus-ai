"""US02 / RF03 at the handler level: REST proxy in, {statusCode, headers, body} out."""

from __future__ import annotations

import json
from datetime import datetime, timezone

import app
import domain
import pytest
from fakes import FakeAssistant, FakeKnowledgeBase, FakeMetrics, FakeStore
from ports import Generation, Passage
from service import ChatService

PASSAGE = Passage(title="Scolarité", uri="s3://kb/scolarite.md", text="Inscriptions en septembre.", score=0.9)


@pytest.fixture
def wired(monkeypatch):
    store = FakeStore()
    seq = iter(f"{i:026d}".replace("0", "A") for i in range(1, 100))

    def make(generation):
        return ChatService(
            store,
            FakeKnowledgeBase([PASSAGE]),
            FakeAssistant(generation),
            thresholds=domain.Thresholds(0.7, 0.7),
            metrics=FakeMetrics(),
            clock=lambda: datetime(2026, 10, 23, 8, 0, 0, tzinfo=timezone.utc),
            id_factory=lambda: next(seq),
        )

    def install(generation):
        monkeypatch.setattr(app, "_build_service", lambda: make(generation))

    return store, install


def event(method, resource, *, claims=None, body=None, path=None, query=None):
    return {
        "httpMethod": method,
        "resource": resource,
        "pathParameters": path,
        "queryStringParameters": query,
        "requestContext": {"authorizer": {"claims": claims or {}}},
        "body": json.dumps(body) if body is not None else None,
    }


STUDENT = {"sub": "student-1", "cognito:groups": "student"}


def test_US02_AC2_post_message_with_token_returns_200_reply(wired):
    _, install = wired
    install(Generation(text="Inscriptions en septembre.", grounding=0.9, relevance=0.9))
    resp = app.handler(
        event("POST", "/chat/messages", claims=STUDENT, body={"message": "Quand s'inscrire ?"}),
        None,
    )
    assert resp["statusCode"] == 200
    out = json.loads(resp["body"])
    assert out["answered"] is True
    assert out["reply"]["content"] == "Inscriptions en septembre."
    assert out["sessionId"]


def test_US02_AC2_missing_token_returns_401(wired):
    _, install = wired
    install(Generation(text="x", grounding=0.9, relevance=0.9))
    resp = app.handler(
        event("POST", "/chat/messages", claims={}, body={"message": "hello"}),
        None,
    )
    assert resp["statusCode"] == 401
    assert json.loads(resp["body"])["code"] == "unauthorized"


def test_US02_AC2_invalid_body_returns_400(wired):
    _, install = wired
    install(Generation(text="x", grounding=0.9, relevance=0.9))
    resp = app.handler(
        event("POST", "/chat/messages", claims=STUDENT, body={"message": ""}),
        None,
    )
    assert resp["statusCode"] == 400
    assert json.loads(resp["body"])["code"] == "validation_error"


def test_RF03_AC3_handler_fallback_sets_answered_false_and_ticket(wired):
    _, install = wired
    install(Generation(text="", grounding=0.1, relevance=0.1, sources=()))
    resp = app.handler(
        event("POST", "/chat/messages", claims=STUDENT, body={"message": "météo ?"}),
        None,
    )
    assert resp["statusCode"] == 200
    out = json.loads(resp["body"])
    assert out["answered"] is False
    assert out["reply"]["content"] == domain.FALLBACK_REPLY
    assert out["ticketSuggestion"]["title"]


def test_US02_AC6_get_other_owner_session_returns_404(wired):
    store, install = wired
    install(Generation(text="ok", grounding=0.9, relevance=0.9))
    # Seed a session owned by someone else.
    store.sessions["ABCDEFGHJKMNPQRSTVWXYZ0123"] = {
        "id": "ABCDEFGHJKMNPQRSTVWXYZ0123",
        "ownerSub": "other",
        "messages": [],
        "createdAt": "2026-10-23T08:00:00Z",
        "updatedAt": "2026-10-23T08:00:00Z",
    }
    resp = app.handler(
        event(
            "GET",
            "/chat/sessions/{sessionId}",
            claims=STUDENT,
            path={"sessionId": "ABCDEFGHJKMNPQRSTVWXYZ0123"},
        ),
        None,
    )
    assert resp["statusCode"] == 404


def test_US08_AC2_delete_history_returns_204(wired):
    store, install = wired
    install(Generation(text="ok", grounding=0.9, relevance=0.9))
    store.sessions["S1"] = {
        "id": "S1", "ownerSub": "student-1", "messages": [],
        "createdAt": "2026-10-23T08:00:00Z", "updatedAt": "2026-10-23T08:00:00Z",
    }
    resp = app.handler(event("DELETE", "/chat/sessions", claims=STUDENT), None)
    assert resp["statusCode"] == 204
    assert store.sessions == {}

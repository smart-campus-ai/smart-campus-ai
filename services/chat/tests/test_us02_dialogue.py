"""US02 — Chatbot dialogue at the service level (offline, in-memory fakes).

Named after the acceptance criteria of issue #2. AC1 (accessible UI) is a frontend
concern verified by EN-85; the backend criteria AC2..AC6 are covered here and in
the handler test.
"""

from __future__ import annotations

from datetime import datetime, timezone

import domain
import pytest
from auth import Caller
from errors import ApiError
from fakes import FakeAssistant, FakeKnowledgeBase, FakeMetrics, FakeStore
from ports import Generation, Passage
from service import ChatService

STUDENT_A = Caller(sub="student-A", groups=("student",))
STUDENT_B = Caller(sub="student-B", groups=("student",))

PASSAGE = Passage(title="Règlement BU", uri="s3://kb/bu.md", text="La BU ouvre à 8h.", score=0.95)


def _service(*, kb_passages=(PASSAGE,), generation=None, store=None, metrics=None):
    gen = generation or Generation(text="La BU ouvre à 8h.", grounding=0.95, relevance=0.95)
    seq = iter(f"{i:026d}".replace("0", "A") for i in range(1, 100))
    return ChatService(
        store or FakeStore(),
        FakeKnowledgeBase(list(kb_passages)),
        FakeAssistant(gen),
        thresholds=domain.Thresholds(grounding=0.7, relevance=0.7),
        metrics=metrics or FakeMetrics(),
        clock=lambda: datetime(2026, 10, 23, 8, 0, 0, tzinfo=timezone.utc),
        id_factory=lambda: next(seq),
    )


def test_US02_AC3_answer_is_built_from_kb_and_cites_sources():
    service = _service()
    resp = service.send_message(STUDENT_A, {"message": "À quelle heure ouvre la BU ?"})
    assert resp["answered"] is True
    assert resp["reply"]["role"] == "assistant"
    assert resp["reply"]["content"] == "La BU ouvre à 8h."
    sources = resp["reply"]["sources"]
    assert sources and sources[0]["title"] == "Règlement BU"
    assert sources[0]["uri"] == "s3://kb/bu.md"
    # Nothing to escalate when the assistant answered.
    assert "ticketSuggestion" not in resp


def test_US02_AC4_no_answer_says_je_ne_sais_pas_and_offers_ticket():
    # Low grounding -> fallback. Also exercises the empty-KB path.
    service = _service(
        kb_passages=(),
        generation=Generation(text="", grounding=0.0, relevance=0.0, sources=()),
    )
    resp = service.send_message(STUDENT_A, {"message": "Quel temps fera-t-il demain ?"})
    assert resp["answered"] is False
    assert resp["reply"]["content"] == domain.FALLBACK_REPLY
    assert resp["reply"].get("sources", []) == []
    assert resp["ticketSuggestion"]["title"]
    assert resp["ticketSuggestion"]["description"]


def test_US02_AC5_history_is_persisted_with_ttl_and_reloads_in_session():
    store = FakeStore()
    service = _service(store=store)
    first = service.send_message(STUDENT_A, {"message": "Première question ?"})
    session_id = first["sessionId"]
    # Continue the same session.
    service.send_message(STUDENT_A, {"sessionId": session_id, "message": "Deuxième question ?"})

    # Reloading the session returns the full transcript (user + assistant turns).
    transcript = service.get_session(STUDENT_A, session_id)
    roles = [m["role"] for m in transcript["messages"]]
    assert roles == ["user", "assistant", "user", "assistant"]

    # Stored with a TTL attribute for the GDPR purge (US08).
    stored = store.sessions[session_id]
    assert "ttl" in stored and isinstance(stored["ttl"], int)
    assert stored["ttl"] > int(datetime(2026, 10, 23, tzinfo=timezone.utc).timestamp())


def test_US02_AC6_sessions_are_isolated_between_students():
    store = FakeStore()
    service = _service(store=store)
    owned = service.send_message(STUDENT_B, {"message": "Question de B ?"})
    session_id = owned["sessionId"]

    # A cannot read B's session: it surfaces as 404, never B's data.
    with pytest.raises(ApiError) as exc:
        service.get_session(STUDENT_A, session_id)
    assert exc.value.status_code == 404

    # A cannot continue B's session either (same 404 isolation).
    with pytest.raises(ApiError) as exc2:
        service.send_message(STUDENT_A, {"sessionId": session_id, "message": "vol de session"})
    assert exc2.value.status_code == 404

    # B still sees only their own session when listing.
    listed_b = service.list_sessions(STUDENT_B, limit=None, cursor=None)
    assert [s["id"] for s in listed_b["items"]] == [session_id]
    listed_a = service.list_sessions(STUDENT_A, limit=None, cursor=None)
    assert listed_a["items"] == []


def test_US02_content_is_never_sent_to_metrics():
    metrics = FakeMetrics()
    service = _service(metrics=metrics)
    service.send_message(STUDENT_A, {"message": "secret à ne pas logguer"})
    # Only counters, keyed by stable metric names — never message content.
    assert metrics.counters.get("chat.message") == 1
    assert all("secret" not in k for k in metrics.counters)

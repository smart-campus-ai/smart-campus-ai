"""US08 — RGPD des historiques de chat (offline). Named after the acceptance criteria.

The retention TTL, the self-service deletion and the self-only scoping are
implemented in the chat service (ttl attribute on write, delete_history,
owner-keyed reads). These tests pin those behaviours to the US08 criteria.

AC4 (Guardrail PII masking in the response *and* in what is stored) and AC5
(Bedrock model-invocation logging disabled or CMK-encrypted with short retention)
are configuration of the Guardrail and the account, not application logic — they
are tracked as infra / needs-decision (see the PR description), not asserted here.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from auth import Caller
from errors import ApiError
from fakes import FakeAssistant, FakeKnowledgeBase, FakeMetrics, FakeStore
from ports import Generation
from service import ChatService

STUDENT_A = Caller(sub="student-A", groups=("student",))
STUDENT_B = Caller(sub="student-B", groups=("student",))

WRITE_TIME = datetime(2026, 10, 23, 8, 0, 0, tzinfo=timezone.utc)


def _service(store, *, ttl_days=30):
    seq = iter(f"{i:026d}".replace("0", "A") for i in range(1, 100))
    return ChatService(
        store,
        FakeKnowledgeBase([]),
        FakeAssistant(Generation(text="", grounding=0.0, relevance=0.0, sources=())),
        ttl_days=ttl_days,
        metrics=FakeMetrics(),
        clock=lambda: WRITE_TIME,
        id_factory=lambda: next(seq),
    )


def test_US08_AC1_ttl_equals_write_time_plus_retention():
    store = FakeStore()
    ttl_days = 30
    resp = _service(store, ttl_days=ttl_days).send_message(STUDENT_A, {"message": "bonjour"})
    stored = store.sessions[resp["sessionId"]]
    expected = int((WRITE_TIME + timedelta(days=ttl_days)).timestamp())
    assert stored["ttl"] == expected


def test_US08_AC1_ttl_follows_configured_retention():
    # A different configured retention yields a different TTL (value is config).
    store = FakeStore()
    resp = _service(store, ttl_days=7).send_message(STUDENT_A, {"message": "bonjour"})
    stored = store.sessions[resp["sessionId"]]
    assert stored["ttl"] == int((WRITE_TIME + timedelta(days=7)).timestamp())


def test_US08_AC2_delete_removes_all_own_sessions_and_history_is_empty():
    store = FakeStore()
    svc = _service(store)
    s1 = svc.send_message(STUDENT_A, {"message": "q1"})["sessionId"]
    s2 = svc.send_message(STUDENT_A, {"message": "q2"})["sessionId"]
    assert s1 in store.sessions and s2 in store.sessions

    removed = svc.delete_history(STUDENT_A)
    assert removed == 2
    # A fresh read of the caller's history is now empty (US08-AC2).
    assert svc.list_sessions(STUDENT_A, limit=None, cursor=None)["items"] == []


def test_US08_AC3_delete_is_scoped_to_self_only():
    store = FakeStore()
    svc = _service(store)
    b_session = svc.send_message(STUDENT_B, {"message": "donnée de B"})["sessionId"]

    # A asks to delete their history: B's sessions are untouched (US08-AC3).
    svc.delete_history(STUDENT_A)
    assert b_session in store.sessions
    assert svc.list_sessions(STUDENT_B, limit=None, cursor=None)["items"] != []


def test_US08_AC3_delete_only_affects_caller_even_with_mixed_owners():
    store = FakeStore()
    svc = _service(store)
    svc.send_message(STUDENT_A, {"message": "a1"})
    svc.send_message(STUDENT_B, {"message": "b1"})
    svc.send_message(STUDENT_A, {"message": "a2"})

    removed = svc.delete_history(STUDENT_A)
    assert removed == 2  # only A's two sessions
    assert len(store.sessions) == 1  # B's one session remains
    remaining = next(iter(store.sessions.values()))
    assert remaining["ownerSub"] == "student-B"

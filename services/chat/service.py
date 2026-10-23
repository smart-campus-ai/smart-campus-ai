"""Application service: orchestrates retrieval, guarded generation and sessions.

Wiring (ports) is injected, so the whole flow runs offline in tests. The service
owns no AWS knowledge. Identity is always the caller's JWT ``sub``; a session id
from the request is only ever used to look up a session *owned by that sub*
(US02-AC6).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import domain
from auth import Caller
from errors import not_found, validation_error
from ports import Assistant, KnowledgeBase, Metrics, Passage, SessionStore
from ulid import new_ulid

_MAX_MESSAGE_LEN = 4000
_MAX_RETRIEVE = 5
_DEFAULT_LIST_LIMIT = 20
_MAX_LIST_LIMIT = 50


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


class _NullMetrics:
    def incr(self, name: str, value: int = 1) -> None:  # noqa: D401
        return None


class ChatService:
    """US02 dialogue + RF03 confinement over a RAG assistant."""

    def __init__(
        self,
        store: SessionStore,
        knowledge_base: KnowledgeBase,
        assistant: Assistant,
        *,
        thresholds: domain.Thresholds | None = None,
        ttl_days: int = 30,
        metrics: Metrics | None = None,
        clock=_utcnow,
        id_factory=new_ulid,
    ) -> None:
        self._store = store
        self._kb = knowledge_base
        self._assistant = assistant
        self._thresholds = thresholds or domain.Thresholds()
        self._ttl_days = ttl_days
        self._metrics = metrics or _NullMetrics()
        self._clock = clock
        self._id = id_factory

    # -- helpers ---------------------------------------------------------------

    def _message(self, role: str, content: str, sources=()) -> dict:
        msg = {
            "id": self._id(),
            "role": role,
            "content": content,
            "createdAt": _iso(self._clock()),
        }
        if sources:
            msg["sources"] = [
                {"title": p.title, "uri": p.uri} for p in sources
            ]
        return msg

    def _load_owned_session(self, caller: Caller, session_id: str) -> dict:
        session = self._store.get_session(caller.sub, session_id)
        # An owner mismatch surfaces as 404, never as another owner's data (US02-AC6).
        if session is None:
            raise not_found("Chat session not found.")
        return session

    # -- commands / queries ----------------------------------------------------

    def send_message(self, caller: Caller, body: object) -> dict:
        if not isinstance(body, dict):
            raise validation_error("Request body must be an object.")
        message = body.get("message")
        if not isinstance(message, str) or not message.strip():
            raise validation_error("A non-empty 'message' is required.")
        if len(message) > _MAX_MESSAGE_LEN:
            raise validation_error(f"'message' exceeds {_MAX_MESSAGE_LEN} characters.")

        now = self._clock()
        session_id = body.get("sessionId")
        if session_id is not None:
            if not isinstance(session_id, str):
                raise validation_error("'sessionId' must be a string.")
            session = self._load_owned_session(caller, session_id)
        else:
            session_id = self._id()
            session = {
                "id": session_id,
                "ownerSub": caller.sub,
                "messages": [],
                "createdAt": _iso(now),
                "updatedAt": _iso(now),
            }

        # RAG: retrieve, then generate under the Guardrail, then confine (RF03).
        passages: list[Passage] = self._kb.retrieve(message, max_results=_MAX_RETRIEVE)
        generation = self._assistant.generate(message, passages)
        decision = domain.decide(generation, self._thresholds)

        self._metrics.incr("chat.message")
        if decision.fallback_reason:
            # Counters only — never the question or the answer (security.md).
            self._metrics.incr(f"chat.fallback.{decision.fallback_reason}")

        user_msg = self._message("user", message)
        reply_msg = self._message("assistant", decision.reply_text, decision.sources)
        session["messages"].extend([user_msg, reply_msg])
        session["updatedAt"] = _iso(now)
        session["ttl"] = int((now + timedelta(days=self._ttl_days)).timestamp())
        if not session.get("title"):
            session["title"] = domain.ticket_suggestion(message, max_title=140)["title"][:140]
        self._store.save_session(session)

        response = {
            "sessionId": session_id,
            "reply": reply_msg,
            "answered": decision.answered,
        }
        if not decision.answered:
            response["ticketSuggestion"] = domain.ticket_suggestion(message)
        return response

    def get_session(self, caller: Caller, session_id: str) -> dict:
        session = self._load_owned_session(caller, session_id)
        return {
            "id": session["id"],
            "ownerSub": session["ownerSub"],
            "messages": session.get("messages", []),
            "createdAt": session["createdAt"],
            "updatedAt": session["updatedAt"],
        }

    def list_sessions(self, caller: Caller, *, limit: int | None, cursor: str | None) -> dict:
        effective = _DEFAULT_LIST_LIMIT if not limit else min(max(limit, 1), _MAX_LIST_LIMIT)
        items, next_cursor = self._store.list_sessions(
            caller.sub, limit=effective, cursor=cursor
        )
        summaries = [
            {
                "id": s["id"],
                "title": s.get("title"),
                "createdAt": s["createdAt"],
                "updatedAt": s["updatedAt"],
            }
            for s in items
        ]
        return {"items": summaries, "nextCursor": next_cursor}

    def delete_history(self, caller: Caller) -> int:
        """Delete all of the caller's sessions (US08-AC2). Only ever their own."""
        removed = self._store.delete_owner_sessions(caller.sub)
        self._metrics.incr("chat.history_deleted")
        return removed

    def ticket_draft(self, caller: Caller, session_id: str) -> dict:
        """Build a prefilled ticket draft from the caller's own session (US10).

        Only the authenticated student's session is used (US10-AC4): the lookup is
        keyed by the JWT ``sub`` and a session owned by someone else surfaces as 404.
        The draft is editable client-side before submission; creation still goes
        through the ``tickets`` POST with its US04 validation (US10-AC3).
        """
        session = self._load_owned_session(caller, session_id)
        self._metrics.incr("chat.ticket_draft")
        return domain.draft_from_session(session.get("messages", []))

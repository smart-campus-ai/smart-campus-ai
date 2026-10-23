"""Ports: the interfaces the chat handler depends on, so the logic is testable offline.

Concrete AWS-backed adapters (DynamoDB ``chat-sessions``, Bedrock Knowledge Base
retrieve, Bedrock Runtime generation with the Guardrail) live in ``adapters.py``
and are only imported at runtime inside the Lambda. Tests inject in-memory fakes
implementing these Protocols, so no test ever touches AWS or Bedrock
(infra/app contract, section 6).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol


@dataclass(frozen=True)
class Passage:
    """A retrieved knowledge-base chunk with its grounding score and citation."""

    title: str
    uri: str | None
    text: str
    score: float


@dataclass(frozen=True)
class Generation:
    """The outcome of a guarded model invocation (Bedrock + Guardrail).

    ``grounding`` and ``relevance`` are the Guardrail contextual-grounding scores in
    [0, 1]. ``blocked`` is True when the Guardrail intervened (denied topic, prompt
    attack, PII) and ``text`` then carries only the neutral canned message (RF03-AC4).
    """

    text: str
    grounding: float
    relevance: float
    blocked: bool = False
    sources: tuple[Passage, ...] = field(default_factory=tuple)


class SessionStore(Protocol):
    """Persistence for the ``chat-sessions`` table (DynamoDB).

    Every item carries a TTL attribute for the GDPR purge (US08). All reads are
    keyed by ``owner_sub`` so a caller can never reach another owner's session
    (US02-AC6); an owner mismatch is surfaced as "not found", never as another
    owner's data.
    """

    def get_session(self, owner_sub: str, session_id: str) -> dict | None:
        """Return the session item for this owner, or None (also when owned by someone else)."""

    def list_sessions(
        self, owner_sub: str, *, limit: int, cursor: str | None
    ) -> tuple[list[dict], str | None]:
        """List the caller's session summaries, newest first. Returns (items, next_cursor)."""

    def save_session(self, session: dict) -> None:
        """Create or replace a session item (must include the TTL attribute)."""

    def delete_owner_sessions(self, owner_sub: str) -> int:
        """Delete every session owned by ``owner_sub`` (GDPR). Returns the count removed."""


class KnowledgeBase(Protocol):
    """Retrieves grounding passages from the Bedrock Knowledge Base (S3 Vectors)."""

    def retrieve(self, query: str, *, max_results: int) -> list[Passage]:
        """Return the top passages for a query (may be empty when nothing matches)."""


class Assistant(Protocol):
    """Generates a guarded, grounded answer from a question and retrieved passages.

    The concrete adapter calls Bedrock Runtime with the Guardrail attached and an
    EU cross-region inference profile. The model id is configuration.
    """

    def generate(self, question: str, passages: list[Passage]) -> Generation: ...


class Metrics(Protocol):
    """Emits counters only. Never receives message content (security.md, US02 NFR)."""

    def incr(self, name: str, value: int = 1) -> None: ...

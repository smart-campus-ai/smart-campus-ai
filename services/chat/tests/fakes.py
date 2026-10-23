"""In-memory fakes of the chat ports, so tests run fully offline (no AWS, no Bedrock)."""

from __future__ import annotations

from ports import Generation, Passage


class FakeStore:
    """In-memory SessionStore keyed by session id. Reads are scoped to owner_sub."""

    def __init__(self) -> None:
        self.sessions: dict[str, dict] = {}

    def get_session(self, owner_sub: str, session_id: str):
        s = self.sessions.get(session_id)
        # Owner mismatch behaves exactly like "absent" (isolation, US02-AC6).
        if s is None or s.get("ownerSub") != owner_sub:
            return None
        return s

    def list_sessions(self, owner_sub: str, *, limit: int, cursor):
        owned = [s for s in self.sessions.values() if s["ownerSub"] == owner_sub]
        owned.sort(key=lambda s: s["updatedAt"], reverse=True)
        start = int(cursor) if cursor else 0
        page = owned[start : start + limit]
        next_cursor = str(start + limit) if start + limit < len(owned) else None
        return page, next_cursor

    def save_session(self, session: dict) -> None:
        self.sessions[session["id"]] = dict(session)

    def delete_owner_sessions(self, owner_sub: str) -> int:
        to_remove = [sid for sid, s in self.sessions.items() if s["ownerSub"] == owner_sub]
        for sid in to_remove:
            del self.sessions[sid]
        return len(to_remove)


class FakeKnowledgeBase:
    """Returns a fixed list of passages, or whatever the test configures."""

    def __init__(self, passages: list[Passage] | None = None) -> None:
        self.passages = passages if passages is not None else []
        self.queries: list[str] = []

    def retrieve(self, query: str, *, max_results: int):
        self.queries.append(query)
        return list(self.passages)[:max_results]


class FakeAssistant:
    """Returns a preset Generation, echoing the retrieved passages as sources."""

    def __init__(self, generation: Generation) -> None:
        self._generation = generation
        self.calls: list[str] = []

    def generate(self, question: str, passages) -> Generation:
        self.calls.append(question)
        gen = self._generation
        # Mirror the real adapter: sources default to the retrieved passages.
        if not gen.sources and passages:
            gen = Generation(
                text=gen.text,
                grounding=gen.grounding,
                relevance=gen.relevance,
                blocked=gen.blocked,
                sources=tuple(passages),
            )
        return gen


class FakeMetrics:
    def __init__(self) -> None:
        self.counters: dict[str, int] = {}
        self.content_seen: list[str] = []  # must stay empty: no content is ever passed

    def incr(self, name: str, value: int = 1) -> None:
        self.counters[name] = self.counters.get(name, 0) + value

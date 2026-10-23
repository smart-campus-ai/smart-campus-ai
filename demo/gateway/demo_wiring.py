"""Builds the shared in-memory services for the demo gateway and seeds them.

Uses each service's OWN classes (from the captured flat modules) so the demo runs
the real domain logic. The in-memory stores mirror the production item shapes
closely enough for the demo; they are not the AWS adapters.
"""

from __future__ import annotations

import sys
from datetime import datetime, timezone

import demo_seed


def _with_modules(captured, fn):
    """Run fn() with a service's flat modules active, then restore."""
    saved = {name: sys.modules.get(name) for name in captured}
    sys.modules.update(captured)
    try:
        return fn()
    finally:
        for name in captured:
            if saved.get(name) is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = saved[name]


# ---- in-memory stores (demo only) -----------------------------------------

class TicketsStore:
    def __init__(self):
        self.items = {}

    def put_ticket(self, meta, event):
        self.items[(meta["pk"], meta["sk"])] = dict(meta)
        self.items[(event["pk"], event["sk"])] = dict(event)

    def get_meta(self, ticket_id):
        return self.items.get((f"TICKET#{ticket_id}", "META"))

    def get_detail(self, ticket_id):
        pk = f"TICKET#{ticket_id}"
        meta = self.items.get((pk, "META"))
        children = [dict(v) for (ipk, isk), v in sorted(self.items.items()) if ipk == pk and isk != "META"]
        return (dict(meta) if meta else None, children)

    def _page(self, metas, ascending, limit, cursor):
        metas = sorted(metas, key=lambda m: m["createdAt"], reverse=not ascending)
        start = int(cursor) if cursor else 0
        page = metas[start:start + limit]
        nxt = str(start + limit) if start + limit < len(metas) else None
        return page, nxt

    def query_by_owner(self, owner_sub, *, status, ascending, limit, cursor):
        metas = [dict(v) for (pk, sk), v in self.items.items() if sk == "META" and v.get("ownerSub") == owner_sub]
        if status:
            metas = [m for m in metas if m["status"] == status]
        return self._page(metas, ascending, limit, cursor)

    def query_by_status(self, status, *, ascending, limit, cursor):
        metas = [dict(v) for (pk, sk), v in self.items.items() if sk == "META"]
        if status:
            metas = [m for m in metas if m["status"] == status]
        return self._page(metas, ascending, limit, cursor)

    def apply_update(self, ticket_id, updated_meta, event_items):
        self.items[(updated_meta["pk"], updated_meta["sk"])] = dict(updated_meta)
        for ev in event_items:
            self.items[(ev["pk"], ev["sk"])] = dict(ev)


class Alerts:
    def __init__(self): self.published = []
    def publish(self, subject, message): self.published.append((subject, message))


class Scheduler:
    def __init__(self): self.schedules = {}
    def schedule_escalation(self, ticket_id, fire_at_iso_utc): self.schedules[ticket_id] = fire_at_iso_utc


class ChatStore:
    def __init__(self): self.sessions = {}
    def get_session(self, owner_sub, session_id):
        s = self.sessions.get(session_id)
        return s if s and s.get("ownerSub") == owner_sub else None
    def list_sessions(self, owner_sub, *, limit, cursor):
        owned = [s for s in self.sessions.values() if s["ownerSub"] == owner_sub]
        owned.sort(key=lambda s: s["updatedAt"], reverse=True)
        start = int(cursor) if cursor else 0
        page = owned[start:start + limit]
        nxt = str(start + limit) if start + limit < len(owned) else None
        return page, nxt
    def save_session(self, session): self.sessions[session["id"]] = dict(session)
    def delete_owner_sessions(self, owner_sub):
        ids = [i for i, s in self.sessions.items() if s["ownerSub"] == owner_sub]
        for i in ids:
            del self.sessions[i]
        return len(ids)


class DemoKnowledgeBase:
    """Tiny keyword 'retrieval' over the seeded demo documents."""
    def __init__(self, Passage, docs): self._Passage = Passage; self._docs = docs
    def retrieve(self, query, *, max_results):
        q = query.lower()
        hits = []
        for title, uri, text, keywords in self._docs:
            if any(k in q for k in keywords):
                hits.append(self._Passage(title=title, uri=uri, text=text, score=0.95))
        return hits[:max_results]


class DemoAssistant:
    """Grounds an answer from retrieved passages; otherwise returns low scores."""
    def __init__(self, Generation): self._Generation = Generation
    def generate(self, question, passages):
        if passages:
            answer = passages[0].text
            return self._Generation(text=answer, grounding=0.95, relevance=0.92, blocked=False, sources=tuple(passages))
        return self._Generation(text="", grounding=0.1, relevance=0.1, blocked=False, sources=())


class KpiStore:
    def __init__(self): self.rows = []
    def read_range(self, from_date, to_date):
        out = []
        for r in self.rows:
            d = datetime.strptime(r["date"], "%Y-%m-%d").date()
            if from_date <= d <= to_date:
                out.append(r)
        return out


# ---- wiring ----------------------------------------------------------------

def wire_and_seed(services: dict):
    tickets_app, tickets_mods = services["tickets"]
    chat_app, chat_mods = services["chat"]
    kpi_app, kpi_mods = services["kpi"]

    # Tickets service (real TicketService + demo stores).
    def build_tickets():
        TicketService = sys.modules["service"].TicketService
        store, alerts, sched = TicketsStore(), Alerts(), Scheduler()
        svc = TicketService(store, alerts, sched)
        return svc, store
    tickets_service, tickets_store = _with_modules(tickets_mods, build_tickets)
    tickets_app._build_service = lambda: tickets_service

    # Chat service (real ChatService + demo stores, KB and assistant).
    def build_chat():
        ChatService = sys.modules["service"].ChatService
        ports = sys.modules["ports"]
        domain = sys.modules["domain"]
        store = ChatStore()
        kb = DemoKnowledgeBase(ports.Passage, demo_seed.KB_DOCS)
        assistant = DemoAssistant(ports.Generation)
        svc = ChatService(store, kb, assistant, thresholds=domain.Thresholds(0.7, 0.7))
        return svc, store
    chat_service, chat_store = _with_modules(chat_mods, build_chat)
    chat_app._build_service = lambda: chat_service

    # KPI service (real KpiService + demo store).
    def build_kpi():
        KpiService = sys.modules["service"].KpiService
        store = KpiStore()
        return KpiService(store), store
    kpi_service, kpi_store = _with_modules(kpi_mods, build_kpi)
    kpi_app._build_service = lambda: kpi_service

    # Seed demo data through each service's own modules (correct item shapes).
    _with_modules(tickets_mods, lambda: demo_seed.seed_tickets(tickets_store))
    _with_modules(chat_mods, lambda: demo_seed.seed_chat(chat_store))
    demo_seed.seed_kpi(kpi_store)

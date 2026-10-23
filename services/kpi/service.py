"""KPI service: read daily aggregates over the range and fold them into the response."""

from __future__ import annotations

import domain
from auth import Caller
from ports import KpiStore


class KpiService:
    def __init__(self, store: KpiStore) -> None:
        self._store = store

    def dashboard(self, caller: Caller, params: dict) -> dict:
        """Return the KPI dashboard for the query. Admin authorization is enforced
        by the handler before this is called (US05-AC5)."""
        query = domain.parse_query(params)
        rows = self._store.read_range(query.from_date, query.to_date)
        return domain.build_response(rows, query)

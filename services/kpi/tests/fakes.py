"""In-memory fake of the kpi store (no AWS). Counts how many day-partitions were
read so tests can assert the O(days) bound (US05-AC4)."""

from __future__ import annotations

import datetime as _dt


class FakeStore:
    def __init__(self, rows: list[dict] | None = None) -> None:
        self.rows = rows or []
        self.days_read = 0

    def read_range(self, from_date: _dt.date, to_date: _dt.date) -> list[dict]:
        # Mirror the adapter: one read per day partition, filtered to the range.
        self.days_read = (to_date - from_date).days + 1
        out = []
        for row in self.rows:
            d = _dt.datetime.strptime(row["date"], "%Y-%m-%d").date()
            if from_date <= d <= to_date:
                out.append(row)
        return out

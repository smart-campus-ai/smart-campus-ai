"""Ports for the kpi function, so the logic is testable offline (no AWS)."""

from __future__ import annotations

import datetime as _dt
from typing import Protocol


class KpiStore(Protocol):
    """Read-only access to the daily-aggregate ``kpi`` table (US05-AC4).

    The IAM role is read-only on this table and has no access to the ``tickets``
    table. ``read_range`` queries by date key so it reads at most O(days × slices)
    items — never a Scan, never the tickets table.
    """

    def read_range(self, from_date: _dt.date, to_date: _dt.date) -> list[dict]:
        """Return every aggregate row whose date is within [from_date, to_date]."""

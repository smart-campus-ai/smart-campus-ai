"""KPI domain: validate the query and fold daily aggregates into the response.

Pure logic, no AWS. The ``kpi`` table holds one aggregate row per (day, status,
category) maintained by ``kpi-aggregator`` from the tickets stream (EN-46). This
function only *reads* those aggregates (never the tickets table, US05-AC4) and
folds them into the contract KpiResponse.

Daily aggregate row (plain dict, already deserialised):
  {
    "date": "2026-10-20",            # YYYY-MM-DD
    "status": "Résolu",              # ticket status this row counts
    "category": "incident",          # ticket category this row counts
    "created": 3,                    # tickets created that day in this slice
    "resolved": 2,                   # tickets resolved that day in this slice
    "resolutionSecondsSum": 7200,    # sum of resolution times for the resolved ones
    "open": 1                        # tickets still open at end of day in this slice
  }
No personal data is stored in an aggregate (US05 NFR).
"""

from __future__ import annotations

import datetime as _dt
from dataclasses import dataclass

GRANULARITIES = ("day", "week", "month")
_DATE_FMT = "%Y-%m-%d"


@dataclass(frozen=True)
class Query:
    from_date: _dt.date
    to_date: _dt.date
    granularity: str
    status: str | None
    category: str | None


def _parse_date(value: str, field: str) -> _dt.date:
    from errors import validation_error

    try:
        return _dt.datetime.strptime(value, _DATE_FMT).date()
    except (TypeError, ValueError):
        raise validation_error(
            "A date parameter is invalid.", [{"field": field, "issue": "must be YYYY-MM-DD"}]
        )


def parse_query(params: dict) -> Query:
    """Validate and normalise the query-string parameters (US05-AC2, AC3)."""
    from errors import validation_error

    raw_from = params.get("from")
    raw_to = params.get("to")
    if not raw_from or not raw_to:
        raise validation_error(
            "The 'from' and 'to' dates are required.",
            [{"field": "from", "issue": "required"}, {"field": "to", "issue": "required"}],
        )
    from_date = _parse_date(raw_from, "from")
    to_date = _parse_date(raw_to, "to")
    if from_date > to_date:
        raise validation_error(
            "'from' must be on or before 'to'.", [{"field": "from", "issue": "after 'to'"}]
        )

    granularity = params.get("granularity") or "day"
    if granularity not in GRANULARITIES:
        raise validation_error(
            "Unsupported granularity.",
            [{"field": "granularity", "issue": f"must be one of {', '.join(GRANULARITIES)}"}],
        )

    return Query(
        from_date=from_date,
        to_date=to_date,
        granularity=granularity,
        status=params.get("status") or None,
        category=params.get("category") or None,
    )


def _bucket_start(day: _dt.date, granularity: str) -> _dt.date:
    if granularity == "day":
        return day
    if granularity == "week":
        # ISO week start (Monday).
        return day - _dt.timedelta(days=day.weekday())
    return day.replace(day=1)  # month


def _matches(row: dict, query: Query) -> bool:
    if query.status is not None and row.get("status") != query.status:
        return False
    if query.category is not None and row.get("category") != query.category:
        return False
    return True


def build_response(rows: list[dict], query: Query) -> dict:
    """Fold daily aggregate rows into the contract KpiResponse.

    ``rows`` are all aggregate rows whose ``date`` is within [from, to]; the caller
    reads at most O(days × slices) items and never the tickets table (US05-AC4).
    """
    total = resolved = open_count = 0
    resolution_sum = 0
    buckets: dict[str, dict] = {}

    for row in rows:
        if not _matches(row, query):
            continue
        created = int(row.get("created", 0))
        res = int(row.get("resolved", 0))
        total += created
        resolved += res
        open_count += int(row.get("open", 0))
        resolution_sum += int(row.get("resolutionSecondsSum", 0))

        day = _dt.datetime.strptime(row["date"], _DATE_FMT).date()
        key = _bucket_start(day, query.granularity).strftime(_DATE_FMT)
        b = buckets.setdefault(key, {"bucket": key, "created": 0, "resolved": 0})
        b["created"] += created
        b["resolved"] += res

    avg = (resolution_sum / resolved) if resolved > 0 else None
    trend = [buckets[k] for k in sorted(buckets)]

    return {
        "range": {
            "from": query.from_date.strftime(_DATE_FMT),
            "to": query.to_date.strftime(_DATE_FMT),
        },
        "granularity": query.granularity,
        "summary": {
            "totalTickets": total,
            "openTickets": open_count,
            "resolvedTickets": resolved,
            "averageResolutionSeconds": avg,
        },
        "trend": trend,
    }

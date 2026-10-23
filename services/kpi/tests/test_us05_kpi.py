"""US05 — Consultation des KPI (offline). Named after the acceptance criteria.

AC3's accessibility note (chart alternative) is satisfied by the `trend` array,
which is the tabular alternative to the charts; the chart rendering itself is
frontend (EN-85).
"""

from __future__ import annotations

import json

import app
import domain
import pytest
from auth import Caller
from errors import ApiError
from fakes import FakeStore
from service import KpiService

ADMIN = Caller(sub="admin-1", groups=("admin",))
ADMIN_CLAIMS = {"sub": "admin-1", "cognito:groups": "admin"}
STUDENT_CLAIMS = {"sub": "student-1", "cognito:groups": "student"}


def _row(date, *, status="Ouvert", category="incident", created=0, resolved=0, res_sum=0, open_=0):
    return {
        "date": date, "status": status, "category": category,
        "created": created, "resolved": resolved,
        "resolutionSecondsSum": res_sum, "open": open_,
    }


ROWS = [
    _row("2026-10-19", status="Ouvert", category="incident", created=2, open_=2),
    _row("2026-10-20", status="Résolu", category="incident", created=1, resolved=2, res_sum=7200, open_=1),
    _row("2026-10-21", status="Résolu", category="besoin", created=3, resolved=1, res_sum=1800, open_=0),
    _row("2026-10-28", status="Ouvert", category="incident", created=5, open_=5),  # next week/month-ish
]


def _params(**kw):
    p = {"from": "2026-10-19", "to": "2026-10-28", "granularity": "day"}
    p.update(kw)
    return p


def test_US05_AC1_headline_indicators():
    out = KpiService(FakeStore(ROWS)).dashboard(ADMIN, _params())
    s = out["summary"]
    assert s["totalTickets"] == 2 + 1 + 3 + 5
    assert s["resolvedTickets"] == 2 + 1
    assert s["openTickets"] == 2 + 1 + 0 + 5
    # avg = (7200 + 1800) / 3 resolved
    assert s["averageResolutionSeconds"] == pytest.approx((7200 + 1800) / 3)


def test_US05_AC1_average_is_null_when_none_resolved():
    rows = [_row("2026-10-19", created=4, open_=4)]
    out = KpiService(FakeStore(rows)).dashboard(ADMIN, _params())
    assert out["summary"]["resolvedTickets"] == 0
    assert out["summary"]["averageResolutionSeconds"] is None


def test_US05_AC2_filter_by_status_and_category():
    out = KpiService(FakeStore(ROWS)).dashboard(ADMIN, _params(status="Résolu", category="incident"))
    # Only the 2026-10-20 Résolu/incident row matches.
    assert out["summary"]["totalTickets"] == 1
    assert out["summary"]["resolvedTickets"] == 2


def test_US05_AC2_filter_by_date_range():
    # Narrow range excludes the 2026-10-28 row.
    out = KpiService(FakeStore(ROWS)).dashboard(ADMIN, {"from": "2026-10-19", "to": "2026-10-21", "granularity": "day"})
    assert out["summary"]["totalTickets"] == 2 + 1 + 3
    assert out["range"] == {"from": "2026-10-19", "to": "2026-10-21"}


def test_US05_AC3_trend_day_granularity():
    out = KpiService(FakeStore(ROWS)).dashboard(ADMIN, _params(granularity="day"))
    buckets = {p["bucket"]: p for p in out["trend"]}
    assert buckets["2026-10-20"]["created"] == 1
    assert buckets["2026-10-20"]["resolved"] == 2
    assert out["granularity"] == "day"


def test_US05_AC3_trend_week_and_month_granularity():
    week = KpiService(FakeStore(ROWS)).dashboard(ADMIN, _params(granularity="week"))
    # 2026-10-19 is a Monday: the first three rows fall in the week starting 2026-10-19.
    wk = {p["bucket"]: p for p in week["trend"]}
    assert "2026-10-19" in wk
    assert wk["2026-10-19"]["created"] == 2 + 1 + 3

    month = KpiService(FakeStore(ROWS)).dashboard(ADMIN, _params(granularity="month"))
    mo = {p["bucket"]: p for p in month["trend"]}
    assert mo["2026-10-01"]["created"] == 2 + 1 + 3 + 5


def test_US05_AC4_reads_at_most_O_days_and_never_tickets():
    store = FakeStore(ROWS)
    KpiService(store).dashboard(ADMIN, _params())
    # 10 days in the range -> at most 10 day-partition reads. No tickets access exists.
    assert store.days_read == 10
    assert not hasattr(store, "tickets")


def test_US05_AC5_student_gets_403(monkeypatch):
    monkeypatch.setattr(app, "_build_service", lambda: KpiService(FakeStore(ROWS)))
    event = {"httpMethod": "GET", "resource": "/kpi",
             "queryStringParameters": _params(),
             "requestContext": {"authorizer": {"claims": STUDENT_CLAIMS}}}
    resp = app.handler(event, None)
    assert resp["statusCode"] == 403
    assert json.loads(resp["body"])["code"] == "forbidden"


def test_US05_AC5_admin_gets_200(monkeypatch):
    monkeypatch.setattr(app, "_build_service", lambda: KpiService(FakeStore(ROWS)))
    event = {"httpMethod": "GET", "resource": "/kpi",
             "queryStringParameters": _params(),
             "requestContext": {"authorizer": {"claims": ADMIN_CLAIMS}}}
    resp = app.handler(event, None)
    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert set(body) == {"range", "granularity", "summary", "trend"}


def test_US05_missing_dates_returns_400(monkeypatch):
    monkeypatch.setattr(app, "_build_service", lambda: KpiService(FakeStore(ROWS)))
    event = {"httpMethod": "GET", "resource": "/kpi",
             "queryStringParameters": {"granularity": "day"},
             "requestContext": {"authorizer": {"claims": ADMIN_CLAIMS}}}
    resp = app.handler(event, None)
    assert resp["statusCode"] == 400


def test_US05_invalid_granularity_returns_400():
    with pytest.raises(ApiError) as exc:
        domain.parse_query({"from": "2026-10-19", "to": "2026-10-20", "granularity": "hour"})
    assert exc.value.status_code == 400

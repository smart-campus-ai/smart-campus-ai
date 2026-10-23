"""US07 — Synchronisation des sources documentaires (offline).

Named after the acceptance criteria of issue #9. AC1 (encrypted storage in the
bucket) and AC4 (a question is answered from a freshly indexed document) are infra
/ end-to-end concerns: AC1 is the bucket's SSE-KMS policy (OpenTofu), AC4 is
verified end-to-end in dev. The function's own criteria are AC2 (auto trigger),
AC3 (manual trigger, admin-only), AC5 (structured log + DLQ) and the anti-duplicate
NFR, all covered here.
"""

from __future__ import annotations

import json

import app
import domain
import pytest
from errors import ApiError, IngestionError
from fakes import FakeIngestion, FakeMetrics
from service import KbSyncService

ADMIN = {"sub": "admin-1", "cognito:groups": "admin"}
STUDENT = {"sub": "student-1", "cognito:groups": "student"}


def _service(ingestion=None, metrics=None):
    return KbSyncService(ingestion or FakeIngestion(), metrics=metrics or FakeMetrics())


# -- AC2: automatic S3 trigger --------------------------------------------------

def test_US07_AC2_s3_event_starts_ingestion_job(monkeypatch):
    ing = FakeIngestion(status=None)
    monkeypatch.setattr(app, "_build_service", lambda: _service(ing))
    event = {"Records": [{"s3": {"bucket": {"name": "sources"}, "object": {"key": "faq.pdf"}}}]}
    out = app.handler(event, None)
    assert out == {"ok": True}
    assert ing.started == 1


# -- AC3: manual admin trigger --------------------------------------------------

def test_US07_AC3_manual_resync_starts_job_and_returns_log(monkeypatch):
    ing = FakeIngestion(status="COMPLETE")
    monkeypatch.setattr(app, "_build_service", lambda: _service(ing))
    event = {"httpMethod": "POST", "resource": "/admin/kb-sync",
             "requestContext": {"authorizer": {"claims": ADMIN}}}
    resp = app.handler(event, None)
    assert resp["statusCode"] == 202
    body = json.loads(resp["body"])
    assert body["status"] == "STARTING"
    assert body["trigger"] == "manual"
    assert body["jobId"] == "job-1"


def test_US07_AC3_manual_resync_is_admin_only(monkeypatch):
    monkeypatch.setattr(app, "_build_service", lambda: _service())
    event = {"httpMethod": "POST", "resource": "/admin/kb-sync",
             "requestContext": {"authorizer": {"claims": STUDENT}}}
    resp = app.handler(event, None)
    assert resp["statusCode"] == 403
    assert json.loads(resp["body"])["code"] == "forbidden"


def test_US07_AC3_manual_resync_requires_auth(monkeypatch):
    monkeypatch.setattr(app, "_build_service", lambda: _service())
    event = {"httpMethod": "POST", "resource": "/admin/kb-sync",
             "requestContext": {"authorizer": {"claims": {}}}}
    resp = app.handler(event, None)
    assert resp["statusCode"] == 401


# -- AC5: structured log + DLQ --------------------------------------------------

def test_US07_AC5_log_record_has_job_status_and_counts():
    record = domain.ingestion_log("job-9", "COMPLETE", trigger="manual", indexed=12, failed=1)
    assert record["jobId"] == "job-9"
    assert record["status"] == "COMPLETE"
    assert record["documentsIndexed"] == 12
    assert record["documentsFailed"] == 1
    assert record["event"] == "kb_ingestion"


def test_US07_AC5_s3_failure_propagates_to_dlq(monkeypatch):
    ing = FakeIngestion(status=None, fail_start=True)
    monkeypatch.setattr(app, "_build_service", lambda: _service(ing))
    event = {"Records": [{"s3": {"bucket": {"name": "sources"}, "object": {"key": "x.pdf"}}}]}
    # The handler re-raises so Lambda routes the record to the on-failure SQS DLQ.
    with pytest.raises(IngestionError):
        app.handler(event, None)


# -- NFR: anti-duplicate debounce ----------------------------------------------

def test_US07_no_duplicate_job_while_one_is_in_flight():
    ing = FakeIngestion(status="IN_PROGRESS")
    svc = _service(ing)
    record = svc.sync(trigger="s3-event")
    assert record["status"] == "DEBOUNCED"
    assert ing.started == 0


def test_US07_starts_when_previous_job_finished():
    for finished in ("COMPLETE", "FAILED", None):
        ing = FakeIngestion(status=finished)
        _service(ing).sync(trigger="s3-event")
        assert ing.started == 1


def test_US07_should_start_decision():
    assert domain.should_start(None) is True
    assert domain.should_start("COMPLETE") is True
    assert domain.should_start("FAILED") is True
    assert domain.should_start("IN_PROGRESS") is False
    assert domain.should_start("STARTING") is False

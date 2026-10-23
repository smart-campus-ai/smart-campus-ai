"""US09 — Notifications e-mail SES (offline). Named after the acceptance criteria."""

from __future__ import annotations

import domain
import pytest
from errors import NotifierError
from fakes import FailingMailer, FakeDirectory, FakeMailer, FakeMetrics
from service import NotifierService

BASE_URL = "https://d123.cloudfront.net"


def _service(directory=None, mailer=None, metrics=None):
    return NotifierService(
        directory or FakeDirectory({"owner-1": "student@school.edu"}),
        mailer or FakeMailer(),
        base_url=BASE_URL,
        metrics=metrics or FakeMetrics(),
    )


def _status_change(old="Ouvert", new="En cours", owner="owner-1"):
    return {
        "eventName": "MODIFY",
        "new": {"pk": "TICKET#T1", "sk": "META", "status": new, "ownerSub": owner, "title": "Wifi HS"},
        "old": {"pk": "TICKET#T1", "sk": "META", "status": old, "ownerSub": owner, "title": "Wifi HS"},
    }


def _student_note(owner="owner-1"):
    return {
        "eventName": "INSERT",
        "new": {"pk": "TICKET#T1", "sk": "NOTE#2026-10-23T08:00:00Z", "audience": "student", "ownerSub": owner, "title": "Wifi HS"},
        "old": {},
    }


def test_US09_AC1_status_change_sends_email():
    mailer = FakeMailer()
    assert _service(mailer=mailer).process_record(_status_change()) is True
    assert len(mailer.sent) == 1
    to, subject, body = mailer.sent[0]
    assert to == "student@school.edu"
    assert "En cours" in subject


def test_US09_AC2_student_note_sends_email():
    mailer = FakeMailer()
    assert _service(mailer=mailer).process_record(_student_note()) is True
    assert len(mailer.sent) == 1
    assert "message" in mailer.sent[0][1].lower()


def test_US09_AC3_email_contains_cloudfront_ticket_link():
    mailer = FakeMailer()
    _service(mailer=mailer).process_record(_status_change())
    body = mailer.sent[0][2]
    assert f"{BASE_URL}/tickets/T1" in body


def test_US09_AC4_non_status_meta_change_is_ignored():
    mailer = FakeMailer()
    # Same status, only another field changed -> no email.
    rec = _status_change(old="Ouvert", new="Ouvert")
    rec["new"]["assigneeSub"] = "admin-9"
    assert _service(mailer=mailer).process_record(rec) is False
    assert mailer.sent == []


def test_US09_AC4_internal_note_is_ignored():
    mailer = FakeMailer()
    rec = _student_note()
    rec["new"]["audience"] = "internal"
    assert _service(mailer=mailer).process_record(rec) is False
    assert mailer.sent == []


def test_US09_AC4_remove_event_is_ignored():
    mailer = FakeMailer()
    rec = _status_change()
    rec["eventName"] = "REMOVE"
    assert _service(mailer=mailer).process_record(rec) is False
    assert mailer.sent == []


def test_US09_AC5_send_failure_raises_notifier_error_for_batch_item_failure():
    svc = _service(mailer=FailingMailer())
    with pytest.raises(NotifierError):
        svc.process_record(_status_change())


def test_US09_unverified_or_missing_address_is_not_an_error():
    # Owner without a verified address (SES sandbox): undeliverable, not a failure.
    svc = _service(directory=FakeDirectory({}))
    assert svc.process_record(_status_change(owner="owner-x")) is False


def test_US09_no_address_and_body_in_metrics():
    metrics = FakeMetrics()
    _service(metrics=metrics).process_record(_status_change())
    assert metrics.counters.get("notifier.sent.status") == 1
    assert all("@" not in k for k in metrics.counters)


def test_US09_handler_returns_partial_batch_failures(monkeypatch):
    import app

    svc = _service(mailer=FailingMailer())
    monkeypatch.setattr(app, "_build_service", lambda: svc)
    # Pre-normalised records bypass the DynamoDB deserialiser; feed app the raw shape
    # by monkeypatching _normalise to identity for the test.
    monkeypatch.setattr(app, "_normalise", lambda r: r["_n"])
    event = {
        "Records": [
            {"eventID": "e1", "dynamodb": {"SequenceNumber": "seq-1"}, "_n": _status_change()},
            {"eventID": "e2", "dynamodb": {"SequenceNumber": "seq-2"}, "_n": _status_change(old="Ouvert", new="Ouvert")},
        ]
    }
    out = app.handler(event, None)
    # Only the failing send (first record) is reported; the ignored one is not.
    assert out["batchItemFailures"] == [{"itemIdentifier": "seq-1"}]


def test_US09_domain_build_email_has_no_pii():
    n = domain.Notification(ticket_id="T1", owner_sub="owner-1", title="Wifi", kind="status", status="Résolu")
    email = domain.build_email(n, BASE_URL)
    # Only title + status + link; no address or ticket body.
    assert "owner-1" not in email["body"]
    assert "Résolu" in email["body"]
    assert f"{BASE_URL}/tickets/T1" in email["body"]

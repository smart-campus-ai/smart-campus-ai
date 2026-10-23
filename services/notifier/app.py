"""Lambda entrypoint for the ``notifier`` function (handler = ``app.handler``).

Triggered by the ``tickets`` DynamoDB stream with event filters (only relevant
changes reach it) and partial batch response enabled. For each record it sends at
most one SES email; a failing record is reported in ``batchItemFailures`` so only
that record is retried, and after retries it goes to the on-failure SQS DLQ
(US09-AC5). Bisect-on-error is configured on the event source mapping (infra).
"""

from __future__ import annotations

import logging

from service import NotifierService

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _build_service() -> NotifierService:
    from adapters import build_from_env

    directory, mailer, base_url, metrics = build_from_env()
    return NotifierService(directory, mailer, base_url=base_url, metrics=metrics)


def _normalise(record: dict) -> dict:
    """Flatten a raw DynamoDB stream record into the shape the domain expects.

    Converts the DynamoDB attribute-value maps (NewImage/OldImage/Keys) into plain
    dicts. Imported lazily so the normalisation stays pure for tests that pass an
    already-normalised record.
    """

    from adapters import deserialise_image

    dynamodb = record.get("dynamodb") or {}
    return {
        "eventName": record.get("eventName"),
        "keys": deserialise_image(dynamodb.get("Keys")),
        "new": deserialise_image(dynamodb.get("NewImage")),
        "old": deserialise_image(dynamodb.get("OldImage")),
    }


def handler(event: dict, context: object) -> dict:
    service = _build_service()
    failures: list[dict] = []

    for record in (event or {}).get("Records", []):
        record_id = record.get("eventID", "")
        try:
            normalised = _normalise(record)
            service.process_record(normalised)
        except Exception:  # noqa: BLE001 — one bad record must not fail the whole batch
            logger.exception("notifier record failed", extra={"eventID": record_id})
            failures.append({"itemIdentifier": record.get("dynamodb", {}).get("SequenceNumber", record_id)})

    # Partial batch response: only the listed records are retried (US09-AC5).
    return {"batchItemFailures": failures}

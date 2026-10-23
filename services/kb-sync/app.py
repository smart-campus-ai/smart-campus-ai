"""Lambda entrypoint for the ``kb-sync`` function (handler = ``app.handler``).

Two triggers share one function:

- **S3 event** (US07-AC2): an object created/updated in the sources bucket. The
  event has ``Records[].s3``. A failure propagates so the record goes to the DLQ
  (US07-AC5). Bursts are debounced (one in-flight job at a time).
- **Admin resync** (US07-AC3): a REST proxy request (admin-only). Returns the
  ingestion log as JSON.
"""

from __future__ import annotations

import logging

import rest
from errors import ApiError, IngestionError, internal_error
from service import KbSyncService

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _build_service() -> KbSyncService:
    from adapters import build_from_env

    ingestion, metrics = build_from_env()
    return KbSyncService(ingestion, metrics=metrics)


def _is_s3_event(event: dict) -> bool:
    records = event.get("Records")
    return bool(records) and isinstance(records, list) and "s3" in (records[0] or {})


def _is_http_event(event: dict) -> bool:
    return "httpMethod" in event or "requestContext" in event and "http" in (event.get("requestContext") or {})


def handler(event: dict, context: object) -> dict:
    event = event or {}

    # S3-event trigger: start (or debounce) one ingestion for the batch.
    if _is_s3_event(event):
        service = _build_service()
        # One job covers all new objects; we start at most one per invocation.
        try:
            service.sync(trigger="s3-event")
        except IngestionError:
            logger.exception("kb-sync S3 ingestion failed")
            raise  # -> on-failure destination / DLQ (US07-AC5)
        return {"ok": True}

    # Admin resync trigger (HTTP).
    request_id = getattr(context, "aws_request_id", None)
    try:
        from auth import caller_from_event, require_admin

        caller = caller_from_event(event)
        require_admin(caller)
        service = _build_service()
        record = service.sync(trigger="manual")
        return rest.json_response(202, record)
    except ApiError as exc:
        return rest.error_response(exc, request_id)
    except IngestionError:
        logger.exception("kb-sync manual ingestion failed")
        return rest.error_response(internal_error("Failed to start ingestion."), request_id)
    except Exception:  # noqa: BLE001
        logger.exception("Unhandled error in kb-sync handler")
        return rest.error_response(internal_error(), request_id)

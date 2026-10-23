"""kb-sync service: start a Bedrock ingestion job unless one is already running.

Shared by both triggers (S3 event, manual admin resync). Returns a structured
result; the caller logs it. Raises IngestionError on a recoverable AWS failure so
the S3-event path can route the record to the DLQ.
"""

from __future__ import annotations

import logging

import domain
from errors import IngestionError
from ports import KnowledgeBaseIngestion, Metrics

logger = logging.getLogger()


class KbSyncService:
    def __init__(self, ingestion: KnowledgeBaseIngestion, *, metrics: Metrics | None = None) -> None:
        self._ingestion = ingestion
        self._metrics = metrics

    def _incr(self, name: str) -> None:
        if self._metrics is not None:
            self._metrics.incr(name)

    def sync(self, *, trigger: str) -> dict:
        """Start an ingestion job unless one is in flight. Returns the log record.

        ``trigger`` is "s3-event" or "manual" (US07-AC2 / AC3).
        """
        try:
            active = self._ingestion.latest_status()
        except Exception as exc:  # noqa: BLE001
            self._incr("kbsync.lookup_failed")
            raise IngestionError("failed to read ingestion status") from exc

        if not domain.should_start(active):
            # A job is already in flight: debounce burst events (US07 NFR).
            self._incr("kbsync.debounced")
            record = domain.ingestion_log(None, "DEBOUNCED", trigger=trigger)
            logger.info("kb ingestion debounced", extra=record)
            return record

        try:
            job = self._ingestion.start()
        except Exception as exc:  # noqa: BLE001
            self._incr("kbsync.start_failed")
            raise IngestionError("failed to start ingestion job") from exc

        self._incr("kbsync.started")
        record = domain.ingestion_log(
            job.job_id, job.status, trigger=trigger, indexed=job.indexed, failed=job.failed
        )
        logger.info("kb ingestion started", extra=record)
        return record

"""kb-sync domain: ingestion debounce decision and structured logging (US07).

Pure logic, no AWS. Bursts of S3 events must not start more than one ingestion
job at a time (US07 NFR): if a job is already running, a new trigger is a no-op
that piggybacks on the in-flight job.
"""

from __future__ import annotations

# Bedrock ingestion job statuses that mean "a job is already in flight"; while one
# of these is active, a new trigger does not start another job (anti-duplicate).
IN_FLIGHT_STATUSES = frozenset({"STARTING", "IN_PROGRESS"})


def should_start(active_status: str | None) -> bool:
    """Decide whether to start a new ingestion job.

    ``active_status`` is the status of the most recent job, or None if there is no
    job yet. Returns False when a job is already in flight (debounce), True
    otherwise.
    """
    if active_status is None:
        return True
    return active_status not in IN_FLIGHT_STATUSES


def ingestion_log(job_id: str | None, status: str, *, trigger: str, indexed: int = 0, failed: int = 0) -> dict:
    """Build the structured JSON log record for an ingestion outcome (US07-AC5).

    Carries the job id, status and document counts; no document content.
    ``trigger`` is "s3-event" or "manual".
    """
    return {
        "event": "kb_ingestion",
        "trigger": trigger,
        "jobId": job_id,
        "status": status,
        "documentsIndexed": indexed,
        "documentsFailed": failed,
    }

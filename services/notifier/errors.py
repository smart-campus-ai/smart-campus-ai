"""Internal errors for the notifier. This function is stream-triggered (no HTTP),
so errors are raised to trigger a batch item failure / DLQ, never serialised to a
client. Kept minimal on purpose.
"""

from __future__ import annotations


class NotifierError(Exception):
    """A recoverable per-record failure. Reported as a batch item failure so only
    the offending record is retried, and sent to the on-failure SQS DLQ after
    retries are exhausted (US09-AC5)."""

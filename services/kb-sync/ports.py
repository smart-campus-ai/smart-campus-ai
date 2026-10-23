"""Ports for kb-sync, so the logic is testable offline (no AWS)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class IngestionJob:
    job_id: str
    status: str
    indexed: int = 0
    failed: int = 0


class KnowledgeBaseIngestion(Protocol):
    """Starts and inspects Bedrock Knowledge Base ingestion jobs.

    The IAM role is limited to StartIngestionJob / ListIngestionJobs /
    GetIngestionJob on the one knowledge base + data source (security.md).
    """

    def latest_status(self) -> str | None:
        """Status of the most recent ingestion job, or None if there is none."""

    def start(self) -> IngestionJob:
        """Start an ingestion job and return its initial descriptor."""


class Metrics(Protocol):
    def incr(self, name: str, value: int = 1) -> None: ...

"""In-memory fakes of the kb-sync ports (no AWS)."""

from __future__ import annotations

from ports import IngestionJob


class FakeIngestion:
    def __init__(self, status=None, *, fail_start=False, fail_lookup=False) -> None:
        self._status = status
        self.fail_start = fail_start
        self.fail_lookup = fail_lookup
        self.started = 0

    def latest_status(self):
        if self.fail_lookup:
            raise RuntimeError("list failed")
        return self._status

    def start(self) -> IngestionJob:
        if self.fail_start:
            raise RuntimeError("start failed")
        self.started += 1
        self._status = "STARTING"
        return IngestionJob(job_id=f"job-{self.started}", status="STARTING", indexed=0, failed=0)


class FakeMetrics:
    def __init__(self) -> None:
        self.counters: dict[str, int] = {}

    def incr(self, name: str, value: int = 1) -> None:
        self.counters[name] = self.counters.get(name, 0) + value

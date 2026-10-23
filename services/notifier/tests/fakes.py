"""In-memory fakes of the notifier ports (no AWS)."""

from __future__ import annotations


class FakeDirectory:
    def __init__(self, mapping: dict[str, str] | None = None) -> None:
        self.mapping = mapping or {}

    def email_for(self, sub: str):
        return self.mapping.get(sub)


class FakeMailer:
    def __init__(self) -> None:
        self.sent: list[tuple[str, str, str]] = []

    def send(self, to_address: str, subject: str, body: str) -> None:
        self.sent.append((to_address, subject, body))


class FailingMailer:
    def send(self, to_address: str, subject: str, body: str) -> None:
        raise RuntimeError("SES unavailable")


class FakeMetrics:
    def __init__(self) -> None:
        self.counters: dict[str, int] = {}

    def incr(self, name: str, value: int = 1) -> None:
        self.counters[name] = self.counters.get(name, 0) + value

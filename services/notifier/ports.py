"""Ports for the notifier, so the logic is testable offline (no AWS)."""

from __future__ import annotations

from typing import Protocol


class EmailDirectory(Protocol):
    """Resolves a Cognito ``sub`` to a verified email address.

    The adapter reads it from the Cognito user pool (AdminGetUser). Returns None
    when the user has no resolvable address; in SES sandbox only verified
    identities can actually receive mail (US09 context).
    """

    def email_for(self, sub: str) -> str | None: ...


class Mailer(Protocol):
    """Sends an email via SES. Raises on failure so the record is retried and,
    after retries, sent to the DLQ (US09-AC5). Never logs the address or body."""

    def send(self, to_address: str, subject: str, body: str) -> None: ...

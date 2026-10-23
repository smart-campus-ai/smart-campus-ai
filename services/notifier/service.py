"""Notifier service: turn a notifiable stream record into one SES email.

Wiring (ports) is injected so the flow runs offline. The service raises
``NotifierError`` on a recoverable failure (address lookup or SES send) so the
handler can report it as a batch item failure; non-notifiable records are a
silent no-op.
"""

from __future__ import annotations

import domain
from errors import NotifierError
from ports import EmailDirectory, Mailer


class NotifierService:
    def __init__(self, directory: EmailDirectory, mailer: Mailer, *, base_url: str, metrics=None) -> None:
        self._directory = directory
        self._mailer = mailer
        self._base_url = base_url
        self._metrics = metrics

    def _incr(self, name: str) -> None:
        if self._metrics is not None:
            self._metrics.incr(name)

    def process_record(self, record: dict) -> bool:
        """Process one stream record. Returns True if an email was sent, False if
        the record was ignored. Raises NotifierError on a recoverable failure."""

        notification = domain.notification_for(record)
        if notification is None:
            self._incr("notifier.ignored")
            return False

        if not notification.owner_sub:
            # Nothing to deliver to; drop rather than fail the batch.
            self._incr("notifier.no_owner")
            return False

        try:
            address = self._directory.email_for(notification.owner_sub)
        except Exception as exc:  # noqa: BLE001 — surface as a retryable failure
            raise NotifierError("email lookup failed") from exc

        if not address:
            # No verified address (SES sandbox): not an error, just undeliverable.
            self._incr("notifier.no_address")
            return False

        email = domain.build_email(notification, self._base_url)
        try:
            self._mailer.send(address, email["subject"], email["body"])
        except Exception as exc:  # noqa: BLE001 — retryable, becomes a batch item failure
            self._incr("notifier.send_failed")
            raise NotifierError("SES send failed") from exc

        self._incr(f"notifier.sent.{notification.kind}")
        return True

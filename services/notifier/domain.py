"""Notifier domain: decide which ticket-stream changes warrant an email (US09).

Pure logic, no AWS. The DynamoDB stream delivers records for the tickets table.
Only two changes are notifiable (US09-AC1, AC2):

- a META item whose ``status`` changed (status update);
- a new NOTE item whose ``audience`` is ``student`` (admin comment to the student).

Everything else is ignored (US09-AC4). The function also runs behind DynamoDB
stream *event filters* so most irrelevant records never reach it; this module is
the second line of defence and the single source of the decision for tests.

No email address or ticket body is handled here, only ids/titles/status, so this
layer never touches PII (US09 NFR).
"""

from __future__ import annotations

from dataclasses import dataclass

SK_META = "META"
SK_NOTE_PREFIX = "NOTE#"
PK_PREFIX = "TICKET#"
NOTE_AUDIENCE_STUDENT = "student"


@dataclass(frozen=True)
class Notification:
    """What to send: resolved from a stream record, before address lookup."""

    ticket_id: str
    owner_sub: str
    title: str
    kind: str  # "status" | "comment"
    status: str | None = None


def _ticket_id_from_pk(pk: str) -> str:
    return pk[len(PK_PREFIX):] if pk.startswith(PK_PREFIX) else pk


def notification_for(record: dict) -> Notification | None:
    """Return the Notification a stream record warrants, or None to ignore it.

    ``record`` is a normalised DynamoDB stream record:
    ``{"eventName": "INSERT|MODIFY|REMOVE", "keys": {...}, "new": {...}, "old": {...}}``
    where ``new``/``old`` are plain dicts (already deserialised from the DynamoDB
    attribute-value shape by the adapter).
    """

    event_name = record.get("eventName")
    if event_name == "REMOVE":
        return None

    new = record.get("new") or {}
    old = record.get("old") or {}
    sk = new.get("sk") or (record.get("keys") or {}).get("sk")
    if not sk:
        return None

    # Status change on the META item (US09-AC1).
    if sk == SK_META:
        new_status = new.get("status")
        old_status = old.get("status")
        if new_status is not None and new_status != old_status:
            return Notification(
                ticket_id=_ticket_id_from_pk(new.get("pk", "")),
                owner_sub=new.get("ownerSub", ""),
                title=new.get("title", ""),
                kind="status",
                status=new_status,
            )
        return None

    # New student-facing note (US09-AC2): only on INSERT, only audience "student".
    if sk.startswith(SK_NOTE_PREFIX):
        if event_name != "INSERT":
            return None
        if new.get("audience") != NOTE_AUDIENCE_STUDENT:
            return None
        return Notification(
            ticket_id=_ticket_id_from_pk(new.get("pk", "")),
            owner_sub=new.get("ownerSub", "") or old.get("ownerSub", ""),
            title=new.get("title", ""),
            kind="comment",
        )

    return None


def ticket_url(base_url: str, ticket_id: str) -> str:
    """Build the CloudFront deep link to a ticket (US09-AC3)."""
    return f"{base_url.rstrip('/')}/tickets/{ticket_id}"


def build_email(notification: Notification, base_url: str) -> dict:
    """Build the email subject/body. No sensitive data beyond title and status
    (US09 NFR); the body carries a CloudFront link, never the ticket content."""

    url = ticket_url(base_url, notification.ticket_id)
    title = notification.title or "votre ticket"
    if notification.kind == "status":
        subject = f"[SmartCampus] Mise à jour de votre ticket : {notification.status}"
        body = (
            f"Bonjour,\n\n"
            f"Le statut de votre ticket « {title} » est passé à : {notification.status}.\n\n"
            f"Consultez le détail ici : {url}\n\n"
            f"— SmartCampus AI"
        )
    else:
        subject = f"[SmartCampus] Nouveau message sur votre ticket"
        body = (
            f"Bonjour,\n\n"
            f"Un administrateur a ajouté un message à votre ticket « {title} ».\n\n"
            f"Consultez-le ici : {url}\n\n"
            f"— SmartCampus AI"
        )
    return {"subject": subject, "body": body}

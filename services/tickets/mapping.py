"""Mapping between DynamoDB items and the contract representations.

Table shape (infra/app contract, section 3):
  pk = "TICKET#<id>", sk = "META" | "EVENT#<ts>" | "NOTE#<ts>"
  GSI by-owner: ownerSub + createdAt ; GSI by-status: status + createdAt
Attribute names (pk, sk, ownerSub, status, createdAt) are fixed by the module.
"""

from __future__ import annotations

PK_PREFIX = "TICKET#"
SK_META = "META"
SK_EVENT_PREFIX = "EVENT#"
SK_NOTE_PREFIX = "NOTE#"


def ticket_pk(ticket_id: str) -> str:
    return f"{PK_PREFIX}{ticket_id}"


def event_sk(timestamp_iso: str, seq: int = 0) -> str:
    # A single update can change several fields at the same instant; the seq suffix
    # keeps each EVENT item's sort key unique while preserving chronological order.
    return f"{SK_EVENT_PREFIX}{timestamp_iso}#{seq:03d}"


def note_sk(timestamp_iso: str) -> str:
    return f"{SK_NOTE_PREFIX}{timestamp_iso}"


def build_meta_item(ticket: dict) -> dict:
    """Serialise a ticket (domain dict) into its META item."""

    item = {
        "pk": ticket_pk(ticket["id"]),
        "sk": SK_META,
        "id": ticket["id"],
        "title": ticket["title"],
        "description": ticket["description"],
        "category": ticket["category"],
        "status": ticket["status"],
        "priority": ticket["priority"],
        "ownerSub": ticket["ownerSub"],
        "createdAt": ticket["createdAt"],
        "updatedAt": ticket["updatedAt"],
    }
    if ticket.get("location") is not None:
        item["location"] = ticket["location"]
    if ticket.get("assigneeSub") is not None:
        item["assigneeSub"] = ticket["assigneeSub"]
    return item


def build_event_item(ticket_id: str, event: dict, seq: int = 0) -> dict:
    """Serialise an AuditEvent into its immutable EVENT item (US01-AC3)."""

    return {
        "pk": ticket_pk(ticket_id),
        "sk": event_sk(event["at"], seq),
        "at": event["at"],
        "actorSub": event["actorSub"],
        "field": event["field"],
        "oldValue": event.get("oldValue"),
        "newValue": event.get("newValue"),
    }


def build_note_item(ticket_id: str, note: dict) -> dict:
    """Serialise a Note into its NOTE item."""

    return {
        "pk": ticket_pk(ticket_id),
        "sk": note_sk(note["createdAt"]),
        "id": note["id"],
        "body": note["body"],
        "audience": note["audience"],
        "authorRole": note["authorRole"],
        "createdAt": note["createdAt"],
    }


def meta_to_summary(item: dict) -> dict:
    """Project a META item to the contract Ticket (list/creation summary)."""

    summary = {
        "id": item["id"],
        "title": item["title"],
        "category": item["category"],
        "status": item["status"],
        "priority": item["priority"],
        "ownerSub": item["ownerSub"],
        "createdAt": item["createdAt"],
        "updatedAt": item["updatedAt"],
    }
    if item.get("location") is not None:
        summary["location"] = item["location"]
    if item.get("assigneeSub") is not None:
        summary["assigneeSub"] = item["assigneeSub"]
    return summary


def note_item_to_note(item: dict) -> dict:
    return {
        "id": item["id"],
        "body": item["body"],
        "audience": item["audience"],
        "authorRole": item["authorRole"],
        "createdAt": item["createdAt"],
    }


def event_item_to_audit(item: dict) -> dict:
    return {
        "at": item["at"],
        "actorSub": item["actorSub"],
        "field": item["field"],
        "oldValue": item.get("oldValue"),
        "newValue": item.get("newValue"),
    }

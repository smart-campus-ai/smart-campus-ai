"""Ticket domain: reference enums and validation rules.

Values are the French reference set from the contract
(packages/contracts/schemas/ticket.json). The handler enforces the business rules
the JSON Schema can only hint at (resolution note, security priority), per US01/US04.
"""

from __future__ import annotations

from errors import validation_error

# --- Reference enums (ticket.json) -----------------------------------------

STATUS_OUVERT = "Ouvert"
STATUS_EN_COURS = "En cours"
STATUS_EN_ATTENTE = "En attente étudiant"
STATUS_RESOLU = "Résolu"
STATUS_FERME = "Fermé"

TICKET_STATUSES: tuple[str, ...] = (
    STATUS_OUVERT,
    STATUS_EN_COURS,
    STATUS_EN_ATTENTE,
    STATUS_RESOLU,
    STATUS_FERME,
)

# Statuses that mean the ticket has been taken in charge (no longer "Ouvert").
# Used by the SLA escalation idempotency check (RF01).
OPEN_STATUS = STATUS_OUVERT

# Moving to one of these requires a resolution note (US01-AC5).
TERMINAL_STATUSES: frozenset[str] = frozenset({STATUS_RESOLU, STATUS_FERME})

TICKET_CATEGORIES: tuple[str, ...] = ("besoin", "incident", "sécurité")
SECURITY_CATEGORY = "sécurité"

PRIORITY_BASSE = "basse"
PRIORITY_NORMALE = "normale"
PRIORITY_HAUTE = "haute"
PRIORITY_CRITIQUE = "critique"
TICKET_PRIORITIES: tuple[str, ...] = (
    PRIORITY_BASSE,
    PRIORITY_NORMALE,
    PRIORITY_HAUTE,
    PRIORITY_CRITIQUE,
)

# Default priority of a freshly created non-security ticket.
DEFAULT_PRIORITY = PRIORITY_NORMALE

NOTE_AUDIENCES: tuple[str, ...] = ("student", "internal")

# Field length bounds mirror the contract schema.
TITLE_MAX = 140
DESCRIPTION_MAX = 5000
LOCATION_MAX = 140
NOTE_BODY_MAX = 4000


def _require_str(value: object, field: str, *, min_len: int, max_len: int) -> str:
    if not isinstance(value, str):
        raise validation_error(
            "A required field is missing or of the wrong type.",
            [{"field": field, "issue": "must be a string"}],
        )
    if not (min_len <= len(value) <= max_len):
        raise validation_error(
            "A field is out of its allowed length.",
            [{"field": field, "issue": f"length must be between {min_len} and {max_len}"}],
        )
    return value


def _require_enum(value: object, field: str, allowed: tuple[str, ...]) -> str:
    if value not in allowed:
        raise validation_error(
            "A field has an unexpected value.",
            [{"field": field, "issue": f"must be one of {', '.join(allowed)}"}],
        )
    return value  # type: ignore[return-value]


def validate_create_request(body: object) -> dict:
    """Validate a CreateTicketRequest; owner/status/priority/id are ignored if sent.

    Returns a normalised dict with title, category, description and optional location.
    """

    if not isinstance(body, dict):
        raise validation_error("Request body must be a JSON object.")

    title = _require_str(body.get("title"), "title", min_len=1, max_len=TITLE_MAX)
    category = _require_enum(body.get("category"), "category", TICKET_CATEGORIES)
    description = _require_str(
        body.get("description"), "description", min_len=1, max_len=DESCRIPTION_MAX
    )

    result: dict = {"title": title, "category": category, "description": description}

    location = body.get("location")
    if location is not None:
        result["location"] = _require_str(
            location, "location", min_len=0, max_len=LOCATION_MAX
        )
    return result


def initial_priority(category: str) -> str:
    """Server-assigned priority on creation: 'critique' for security (US04-AC5)."""

    return PRIORITY_CRITIQUE if category == SECURITY_CATEGORY else DEFAULT_PRIORITY


def validate_update_request(body: object) -> dict:
    """Validate an UpdateTicketRequest (admin, US01).

    At least one field is required. A move to a terminal status requires a note
    (checked here because it is a cross-field rule the schema cannot express),
    returning 400 otherwise (US01-AC5).
    """

    if not isinstance(body, dict):
        raise validation_error("Request body must be a JSON object.")

    allowed_fields = {"status", "priority", "assigneeSub", "note"}
    unknown = set(body) - allowed_fields
    if unknown:
        raise validation_error(
            "Unexpected field in update.",
            [{"field": f, "issue": "not allowed"} for f in sorted(unknown)],
        )
    if not body:
        raise validation_error("At least one field must be provided.")

    result: dict = {}
    if "status" in body:
        result["status"] = _require_enum(body["status"], "status", TICKET_STATUSES)
    if "priority" in body:
        result["priority"] = _require_enum(body["priority"], "priority", TICKET_PRIORITIES)
    if "assigneeSub" in body:
        result["assigneeSub"] = _require_str(
            body["assigneeSub"], "assigneeSub", min_len=1, max_len=128
        )
    if "note" in body:
        note = body["note"]
        if not isinstance(note, dict):
            raise validation_error(
                "note must be an object.", [{"field": "note", "issue": "must be an object"}]
            )
        note_body = _require_str(note.get("body"), "note.body", min_len=1, max_len=NOTE_BODY_MAX)
        note_audience = _require_enum(note.get("audience"), "note.audience", NOTE_AUDIENCES)
        result["note"] = {"body": note_body, "audience": note_audience}

    target_status = result.get("status")
    if target_status in TERMINAL_STATUSES:
        note = result.get("note")
        if note is None or note.get("audience") != "student":
            raise validation_error(
                "Moving to a terminal status requires a resolution note for the student.",
                [{"field": "note", "issue": "a student-facing resolution note is required"}],
            )

    return result

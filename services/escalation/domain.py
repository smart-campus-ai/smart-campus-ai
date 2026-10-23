"""Escalation domain: SLA status/priority rules (RF01).

These mirror the reference values of the ticket contract
(packages/contracts/schemas/ticket.json). They are duplicated here on purpose:
each Lambda archive is self-contained (infra/app contract, section 5), so the
escalation function does not import from the tickets function.
"""

from __future__ import annotations

STATUS_OUVERT = "Ouvert"

PRIORITY_BASSE = "basse"
PRIORITY_NORMALE = "normale"
PRIORITY_HAUTE = "haute"
PRIORITY_CRITIQUE = "critique"

# Escalation raises the priority by one level, capped at "critique" (RF01-AC3).
# The exact rule is a PO decision; this ladder is the current working set and lives
# in one place so it can change in a single edit.
_PRIORITY_LADDER = (PRIORITY_BASSE, PRIORITY_NORMALE, PRIORITY_HAUTE, PRIORITY_CRITIQUE)


def escalated_priority(current: str) -> str:
    """Return the priority after escalation: one level up, capped at 'critique'."""

    try:
        index = _PRIORITY_LADDER.index(current)
    except ValueError:
        # Unknown priority: escalate to the top rather than guess.
        return PRIORITY_CRITIQUE
    return _PRIORITY_LADDER[min(index + 1, len(_PRIORITY_LADDER) - 1)]


def is_open(status: str) -> bool:
    return status == STATUS_OUVERT

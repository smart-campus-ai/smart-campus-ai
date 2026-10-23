"""Domain logic for the chat assistant: RAG confinement and grounding (US02, RF03).

This module is pure: no AWS, no I/O, no clock. It decides, from the Guardrail
scores and the retrieved passages, whether an answer is sufficiently grounded to
be returned, or whether the assistant must fall back to "je ne sais pas" and offer
a ticket (RF03-AC3). Thresholds are configuration and are validated to lie in
[0, 1] (RF03-AC5).
"""

from __future__ import annotations

from dataclasses import dataclass

from ports import Generation, Passage

# Shown verbatim to the student when the answer is not grounded (US02-AC4 / RF03-AC3).
FALLBACK_REPLY = "Je ne sais pas."
# Shown when the Guardrail blocks a denied topic or a prompt-injection attempt (RF03-AC4).
BLOCKED_REPLY = "Je ne peux pas répondre à cette demande."


@dataclass(frozen=True)
class Thresholds:
    """Guardrail contextual-grounding thresholds, both in [0, 1] (RF03-AC2, AC5).

    An answer is kept only when its grounding score is at least ``grounding`` and
    its relevance score at least ``relevance``. Calibrated on the demo question set
    (EN-95); defaults are deliberately conservative.
    """

    grounding: float = 0.7
    relevance: float = 0.7

    def __post_init__(self) -> None:
        for name in ("grounding", "relevance"):
            value = getattr(self, name)
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                raise ValueError(f"threshold '{name}' must be a number")
            if not (0.0 <= float(value) <= 1.0):
                raise ValueError(f"threshold '{name}' must be within [0, 1], got {value!r}")


@dataclass(frozen=True)
class Decision:
    """The outcome applied to a generation: the reply text, whether it is answered,
    and the sources to cite (only when answered and grounded)."""

    reply_text: str
    answered: bool
    sources: tuple[Passage, ...]
    # Metric name describing why we fell back, or None when answered. No content.
    fallback_reason: str | None = None


def ticket_suggestion(question: str, *, max_title: int = 140, max_description: int = 5000) -> dict:
    """Build a prefilled ticket draft from the unanswered question (US10-AC2)."""

    normalised = " ".join(question.split())
    title = normalised[:max_title] if normalised else "Demande d'assistance"
    return {"title": title, "description": normalised[:max_description]}


def draft_from_session(
    messages: list[dict], *, max_title: int = 140, max_description: int = 5000
) -> dict:
    """Summarise a conversation into a prefilled ticket draft (US10-AC2).

    The summary uses only the messages already stored for the session (which the
    Guardrail has PII-masked, US08-AC4), so no new PII is introduced. The title
    comes from the student's first question; the description concatenates the
    student's turns (what they tried to get help with). The student can edit
    everything before submitting (US10-AC2/AC3). The caller filtering (AC4) is
    enforced by the service, which only ever passes the owner's own session here.
    """

    user_turns = [
        " ".join(str(m.get("content", "")).split())
        for m in messages
        if m.get("role") == "user" and str(m.get("content", "")).strip()
    ]
    if not user_turns:
        return {"title": "Demande d'assistance", "description": ""}

    title = user_turns[0][:max_title]
    description = "\n".join(user_turns)[:max_description]
    return {"title": title, "description": description}


def decide(generation: Generation, thresholds: Thresholds) -> Decision:
    """Apply RF03 confinement to a model generation.

    Order matters: a Guardrail block (denied topic / prompt injection) wins over any
    score (RF03-AC4); otherwise the answer must clear both thresholds and be backed
    by at least one passage to be returned with its citations (US02-AC3, RF03-AC1).
    """

    if generation.blocked:
        return Decision(
            reply_text=BLOCKED_REPLY,
            answered=False,
            sources=(),
            fallback_reason="guardrail_blocked",
        )

    grounded = (
        generation.grounding >= thresholds.grounding
        and generation.relevance >= thresholds.relevance
        and len(generation.sources) > 0
        and generation.text.strip() != ""
    )
    if not grounded:
        return Decision(
            reply_text=FALLBACK_REPLY,
            answered=False,
            sources=(),
            fallback_reason="below_threshold",
        )

    return Decision(
        reply_text=generation.text,
        answered=True,
        sources=generation.sources,
        fallback_reason=None,
    )

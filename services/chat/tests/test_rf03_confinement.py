"""RF03 — RAG confinement, grounding thresholds and fallback, at the domain level.

Pure-logic tests of ``domain``: no AWS, no service wiring. Named after the
acceptance criteria of issue #12.
"""

from __future__ import annotations

import domain
import pytest
from ports import Generation, Passage

PASSAGE = Passage(title="Horaires BU", uri="s3://kb/bu.md", text="La BU ouvre à 8h.", score=0.9)


def _gen(text="La BU ouvre à 8h.", grounding=0.9, relevance=0.9, blocked=False, sources=(PASSAGE,)):
    return Generation(
        text=text, grounding=grounding, relevance=relevance, blocked=blocked, sources=sources
    )


def test_RF03_AC1_answer_only_from_knowledge_base_passages():
    # With no retrieved passage there is nothing to ground on: never answered.
    decision = domain.decide(_gen(sources=()), domain.Thresholds())
    assert decision.answered is False
    assert decision.sources == ()
    assert decision.reply_text == domain.FALLBACK_REPLY


def test_RF03_AC2_grounding_and_relevance_thresholds_are_applied():
    thresholds = domain.Thresholds(grounding=0.8, relevance=0.8)
    # Grounding below threshold -> not answered, even though relevance is high.
    low_grounding = domain.decide(_gen(grounding=0.5, relevance=0.95), thresholds)
    assert low_grounding.answered is False
    # Relevance below threshold -> not answered, even though grounding is high.
    low_relevance = domain.decide(_gen(grounding=0.95, relevance=0.5), thresholds)
    assert low_relevance.answered is False
    # Both at or above threshold -> answered with citations.
    ok = domain.decide(_gen(grounding=0.8, relevance=0.8), thresholds)
    assert ok.answered is True
    assert ok.sources and ok.sources[0].title == "Horaires BU"


def test_RF03_AC3_below_threshold_falls_back_and_offers_ticket():
    decision = domain.decide(_gen(grounding=0.1, relevance=0.1), domain.Thresholds())
    assert decision.answered is False
    assert decision.reply_text == domain.FALLBACK_REPLY
    assert decision.fallback_reason == "below_threshold"
    # The ticket draft is derived from the question, not the (absent) answer.
    draft = domain.ticket_suggestion("où est la cafétéria ?")
    assert draft["title"] and draft["description"]


def test_RF03_AC4_guardrail_block_wins_over_scores_and_returns_neutral_reply():
    # A blocked generation (denied topic / prompt injection) is refused regardless
    # of how high its scores are.
    decision = domain.decide(_gen(blocked=True, grounding=1.0, relevance=1.0), domain.Thresholds())
    assert decision.answered is False
    assert decision.reply_text == domain.BLOCKED_REPLY
    assert decision.fallback_reason == "guardrail_blocked"
    assert decision.sources == ()


def test_RF03_AC5_thresholds_outside_unit_interval_are_rejected():
    for bad in (-0.1, 1.1, 2.0, -1.0):
        with pytest.raises(ValueError):
            domain.Thresholds(grounding=bad, relevance=0.5)
        with pytest.raises(ValueError):
            domain.Thresholds(grounding=0.5, relevance=bad)
    # Booleans are not valid numeric thresholds.
    with pytest.raises(ValueError):
        domain.Thresholds(grounding=True, relevance=0.5)
    # Bounds are inclusive: 0 and 1 are valid.
    assert domain.Thresholds(grounding=0.0, relevance=1.0)

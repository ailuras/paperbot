"""Daily paper recommendation engine."""

from __future__ import annotations

import random
from datetime import date, datetime, timedelta
from typing import Any

from paperbot.config import RecommendationConfig, Settings


def _parse_pub_date(paper: dict[str, Any]) -> date | None:
    value = paper.get("publication_date") or ""
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError:
        return None


def _is_recent(paper: dict[str, Any], cutoff: date) -> bool:
    pub_date = _parse_pub_date(paper)
    return pub_date is not None and pub_date >= cutoff


def _paper_key(paper: dict[str, Any]) -> str:
    return paper.get("id") or paper.get("doi") or paper.get("title") or ""


class RecommendationResult:
    """A single recommended paper with metadata."""

    def __init__(
        self,
        paper: dict[str, Any],
        reason: str,
        slot_index: int,
    ):
        self.paper = paper
        self.reason = reason
        self.slot_index = slot_index

    @property
    def paper_id(self) -> str:
        return self.paper.get("id") or ""


def recommend_papers(
    papers: list[dict[str, Any]],
    settings: Settings,
    count: int | None = None,
) -> list[RecommendationResult]:
    """Select papers for daily recommendation.

    Strategy:
    1. Quality slots prefer papers at or above the score threshold.
    2. Remaining slots prefer recent papers.
    3. Each slot falls back to broader pool if preferred pool is empty.
    """
    rec = settings.recommendation
    daily_count = count or rec.daily_count
    quality_slots = min(rec.quality_slots, daily_count)
    high_threshold = rec.high_score_threshold
    recent_days = rec.recent_days

    if not papers:
        return []

    recent_cutoff = date.today() - timedelta(days=recent_days)
    recent_pool = [p for p in papers if _is_recent(p, recent_cutoff)]
    high_score_pool = [p for p in papers if (p.get("score", 0) or 0) >= high_threshold]

    exclude_ids: set[str] = set()
    selected: list[RecommendationResult] = []

    def _pop_random(pool: list[dict[str, Any]]) -> dict[str, Any] | None:
        valid = [p for p in pool if _paper_key(p) not in exclude_ids]
        if not valid:
            return None
        return random.choice(valid)

    # Quality priority slots
    for i in range(quality_slots):
        px = _pop_random(high_score_pool)
        reason = f"Quality Pick (score >= {high_threshold:g})"
        if px is None:
            px = _pop_random(recent_pool)
            reason = f"Recent Pick (last {recent_days}d)"
        if px is None:
            px = _pop_random(papers)
            reason = "Exploration Pick"
        if px:
            selected.append(RecommendationResult(px, reason, i))
            exclude_ids.add(_paper_key(px))

    # Recency priority slots
    for i in range(quality_slots, daily_count):
        px = _pop_random(recent_pool)
        reason = f"Recent Pick (last {recent_days}d)"
        if px is None:
            px = _pop_random(papers)
            reason = "Exploration Pick"
        if px:
            selected.append(RecommendationResult(px, reason, i))
            exclude_ids.add(_paper_key(px))

    return selected

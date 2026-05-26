"""Tests for the recommendation engine."""

from __future__ import annotations

from datetime import date, timedelta

from paperbot.config import RecommendationConfig, Settings, TrackConfig
from paperbot.models import Paper
from paperbot.recommend import recommend_papers


def _make_paper(pid: str, score: float, pub_date: str) -> Paper:
    return Paper(
        id=pid,
        title=f"Paper {pid}",
        publication_date=pub_date,
        publication_year=int(pub_date[:4]),
        score=score,
        cited_by_count=0,
        venue="CAV",
        track="SMT",
    )


def test_recommend_quality_slots():
    """Quality slots prefer high-score papers."""
    cfg = Settings(
        tracks={"T": TrackConfig(query="q", keywords=["k"])},
        scoring={
            "tiers": {"1": {"points": 5, "acronyms": ["CAV"], "phrases": []}},
            "citation_breakpoints": [{"up_to": None, "points_per_citation": 0.1}],
        },
        recommendation=RecommendationConfig(daily_count=3, quality_slots=1, high_score_threshold=5, recent_days=30),
    )
    today = date.today().isoformat()
    papers = [
        _make_paper("W1", 10.0, today),
        _make_paper("W2", 2.0, today),
        _make_paper("W3", 1.0, today),
    ]
    results = recommend_papers(papers, cfg)
    assert len(results) == 3
    # First slot should be the high-score paper
    assert results[0].paper.id == "W1"
    assert "Quality" in results[0].reason


def test_recommend_recent_fallback():
    """When no high-score papers, slots fall back to recent."""
    cfg = Settings(
        tracks={"T": TrackConfig(query="q", keywords=["k"])},
        scoring={
            "tiers": {"1": {"points": 5, "acronyms": ["CAV"], "phrases": []}},
            "citation_breakpoints": [{"up_to": None, "points_per_citation": 0.1}],
        },
        recommendation=RecommendationConfig(daily_count=2, quality_slots=1, high_score_threshold=10, recent_days=30),
    )
    today = date.today().isoformat()
    old = (date.today() - timedelta(days=60)).isoformat()
    papers = [
        _make_paper("W1", 2.0, today),
        _make_paper("W2", 1.0, old),
    ]
    results = recommend_papers(papers, cfg)
    assert len(results) == 2
    # Both are below threshold, so recency picks
    ids = {r.paper.id for r in results}
    assert ids == {"W1", "W2"}


def test_recommend_no_duplicates():
    """Same paper is not recommended twice."""
    cfg = Settings(
        tracks={"T": TrackConfig(query="q", keywords=["k"])},
        scoring={
            "tiers": {"1": {"points": 5, "acronyms": ["CAV"], "phrases": []}},
            "citation_breakpoints": [{"up_to": None, "points_per_citation": 0.1}],
        },
        recommendation=RecommendationConfig(daily_count=3, quality_slots=1, high_score_threshold=1, recent_days=30),
    )
    today = date.today().isoformat()
    papers = [
        _make_paper("W1", 5.0, today),
        _make_paper("W2", 4.0, today),
    ]
    results = recommend_papers(papers, cfg)
    ids = [r.paper.id for r in results]
    assert len(ids) == len(set(ids))


def test_recommend_empty_pool():
    """Empty paper list returns empty results."""
    cfg = Settings(
        tracks={"T": TrackConfig(query="q", keywords=["k"])},
        scoring={
            "tiers": {"1": {"points": 5, "acronyms": ["CAV"], "phrases": []}},
            "citation_breakpoints": [{"up_to": None, "points_per_citation": 0.1}],
        },
        recommendation=RecommendationConfig(daily_count=3, quality_slots=1, high_score_threshold=5, recent_days=30),
    )
    results = recommend_papers([], cfg)
    assert results == []


def test_recommend_custom_count():
    """count parameter overrides daily_count."""
    cfg = Settings(
        tracks={"T": TrackConfig(query="q", keywords=["k"])},
        scoring={
            "tiers": {"1": {"points": 5, "acronyms": ["CAV"], "phrases": []}},
            "citation_breakpoints": [{"up_to": None, "points_per_citation": 0.1}],
        },
        recommendation=RecommendationConfig(daily_count=5, quality_slots=1, high_score_threshold=1, recent_days=30),
    )
    today = date.today().isoformat()
    papers = [_make_paper(f"W{i}", float(i), today) for i in range(1, 10)]
    results = recommend_papers(papers, cfg, count=2)
    assert len(results) == 2

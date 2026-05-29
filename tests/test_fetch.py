"""Tests for OpenAlex fetching and paper scoring."""

from __future__ import annotations

from pathlib import Path

from paperbot.config import load_config
from paperbot.config import Settings
from paperbot.fetch import (
    VenueScorer,
    _dedupe_and_merge_tracks,
    _is_relevant,
    _parse_work,
    _restore_abstract,
)
from paperbot.models import Paper


def test_venue_scorer_acronym_match(sample_config_dict: dict):
    """VenueScorer matches acronyms in venue names."""
    cfg = Settings(**sample_config_dict)
    scorer = VenueScorer(cfg)
    assert scorer.get_tier("Proceedings of CAV 2024") == 1
    assert scorer.get_tier("TACAS 2023") == 2


def test_default_config_treats_top_venue_short_names_as_expected_tiers():
    """Default scoring keeps common short venue names at their configured tiers."""
    cfg_path = Path(__file__).resolve().parents[1] / "data" / "config.json.example"
    cfg = load_config(cfg_path)
    scorer = VenueScorer(cfg)

    expected = {
        "SAT 2024": 1,
        "CP 2024": 1,
        "IJCAR 2024": 1,
        "CADE 2024": 1,
        "FM 2024": 1,
        "CCS 2024": 1,
        "IEEE S&P 2024": 1,
        "TSE 2024": 1,
        "TOSEM 2024": 1,
        "TOPLAS 2024": 1,
        "JAIR 2024": 1,
        "AIJ 2024": 1,
    }
    for venue, tier in expected.items():
        assert scorer.get_tier(venue) == tier


def test_default_config_prefers_specific_lower_tier_official_names():
    """Specific tier-2 venue names should beat broader tier-1 substrings."""
    cfg_path = Path(__file__).resolve().parents[1] / "data" / "config.json.example"
    cfg = load_config(cfg_path)
    scorer = VenueScorer(cfg)

    expected = {
        "International Symposium on Formal Methods in Computer-Aided Design": 2,
        "International Conference on Integration of Constraint Programming, Artificial Intelligence, and Operations Research": 2,
        "International Conference on the Integration of Constraint Programming, Artificial Intelligence, and Operations Research": 2,
        "International Conference on Logic for Programming, Artificial Intelligence and Reasoning": 2,
        "International Conference on Verification, Model Checking, and Abstract Interpretation": 2,
    }
    for venue, tier in expected.items():
        assert scorer.get_tier(venue) == tier


def test_venue_scorer_phrase_match(sample_config_dict: dict):
    """VenueScorer matches phrase-based tiers."""
    cfg = Settings(
        **{
            **sample_config_dict,
            "scoring": {
                "tiers": {
                    "1": {"points": 5, "acronyms": [], "phrases": ["computer aided verification"]},
                },
                "citation_breakpoints": [
                    {"up_to": None, "points_per_citation": 0.1},
                ],
            },
        }
    )
    scorer = VenueScorer(cfg)
    assert scorer.get_tier("International Conference on Computer Aided Verification") == 1


def test_venue_scorer_blacklist(sample_config_dict: dict):
    """Blacklisted venues get tier 0."""
    cfg = Settings(
        **{
            **sample_config_dict,
            "filters": {"venue_blacklist": ["arxiv"], "title_blacklist": [], "source_blacklist": []},
        }
    )
    scorer = VenueScorer(cfg)
    assert scorer.get_tier("arXiv preprint") == 0


def test_venue_scorer_no_match():
    """Unknown venues get tier 0."""
    from paperbot.config import Settings, TrackConfig

    cfg = Settings(
        tracks={"T": TrackConfig(query="q", keywords=["k"])},
        scoring={
            "tiers": {"1": {"points": 5, "acronyms": ["CAV"], "phrases": []}},
            "citation_breakpoints": [{"up_to": None, "points_per_citation": 0.1}],
        },
    )
    scorer = VenueScorer(cfg)
    assert scorer.get_tier("Random Workshop") == 0
    assert scorer.get_tier("") == 0


def test_citation_score_breakpoints(sample_config_dict: dict):
    """Citation scoring respects breakpoints."""
    cfg = Settings(**sample_config_dict)
    scorer = VenueScorer(cfg)

    # 0 citations = 0 points
    assert scorer.citation_score(0) == 0.0
    # 10 citations at 0.5/pt = 5 points
    assert scorer.citation_score(10) == 5.0
    # 20 citations: 10@0.5 + 10@0.1 = 6 points
    assert scorer.citation_score(20) == 6.0


def test_calculate_score(sample_config_dict: dict):
    """Total score = tier base + citation score."""
    cfg = Settings(**sample_config_dict)
    scorer = VenueScorer(cfg)

    # CAV (tier 1 = 5 pts) + 10 citations (5 pts) = 10
    assert scorer.calculate_score("CAV 2024", 10) == 10.0
    # Unknown venue (tier 0 = 0 pts) + 10 citations (5 pts) = 5
    assert scorer.calculate_score("Random", 10) == 5.0


def test_restore_abstract():
    """Abstract is reconstructed from inverted index."""
    inverted = {
        "This": [0],
        "is": [1],
        "a": [2],
        "test": [3],
    }
    assert _restore_abstract(inverted) == "This is a test"


def test_restore_abstract_empty():
    """Empty or None inverted index returns empty string."""
    assert _restore_abstract({}) == ""
    assert _restore_abstract(None) == ""


def test_is_relevant_keyword_match(sample_config_dict: dict):
    """_is_relevant matches keywords with word boundaries."""
    cfg = Settings(**sample_config_dict)
    paper = Paper(title="A New SMT Solver", abstract="We present a solver.", venue="CAV")
    assert _is_relevant(paper, "SMT", cfg) is True


def test_is_relevant_no_match(sample_config_dict: dict):
    """_is_relevant rejects papers without track keywords."""
    cfg = Settings(**sample_config_dict)
    paper = Paper(title="Neural Networks", abstract="Deep learning.", venue="NeurIPS")
    assert _is_relevant(paper, "SMT", cfg) is False


def test_is_relevant_title_blacklist(sample_config_dict: dict):
    """Title blacklist filters out papers."""
    cfg = Settings(
        **{
            **sample_config_dict,
            "filters": {
                "title_blacklist": ["survey"],
                "source_blacklist": [],
                "venue_blacklist": [],
            },
        }
    )
    paper = Paper(title="A Survey of SMT Solvers", abstract="", venue="CAV")
    assert _is_relevant(paper, "SMT", cfg) is False


def test_dedupe_and_merge_tracks():
    """Duplicate papers by id are merged, tracks combined."""
    papers = [
        Paper(id="W1", title="Paper", track="SMT", score=5.0),
        Paper(id="W1", title="Paper", track="SAT", score=3.0),
        Paper(id="W2", title="Other", track="CP", score=1.0),
    ]
    result = _dedupe_and_merge_tracks(papers)
    assert len(result) == 2

    w1 = next(p for p in result if p.id == "W1")
    assert w1.track == "SAT,SMT"  # sorted alphabetically
    assert w1.score == 5.0  # higher score wins


def test_parse_work(sample_config_dict: dict):
    """_parse_work extracts fields from OpenAlex work JSON."""
    cfg = Settings(**sample_config_dict)
    scorer = VenueScorer(cfg)

    work = {
        "id": "https://openalex.org/W123",
        "doi": "10.1000/test",
        "display_name": "Test Paper",
        "authorships": [
            {"author": {"display_name": "Alice"}},
            {"author": {"display_name": "Bob"}},
        ],
        "publication_year": 2024,
        "publication_date": "2024-03-15",
        "cited_by_count": 50,
        "abstract_inverted_index": {"This": [0], "is": [1], "test": [2]},
        "primary_location": {
            "source": {"display_name": "CAV 2024"},
            "landing_page_url": "https://example.com",
            "pdf_url": "https://example.com/pdf",
        },
        "open_access": {"oa_url": "https://oa.example.com"},
    }
    paper = _parse_work(work, "SMT", scorer)
    assert paper.id == "https://openalex.org/W123"
    assert paper.title == "Test Paper"
    assert paper.authors == ["Alice", "Bob"]
    assert paper.track == "SMT"
    assert paper.tier == 1
    assert paper.abstract == "This is test"
    assert paper.landing_page_url == "https://example.com"
    assert paper.pdf_url == "https://example.com/pdf"

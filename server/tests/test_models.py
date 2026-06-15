"""Tests for PaperBot domain models."""

from __future__ import annotations

from paperbot.models import Paper, PaperStatus


def test_paper_status_constants():
    """PaperStatus defines the expected statuses."""
    assert PaperStatus.PENDING == "pending"
    assert PaperStatus.READ == "read"
    assert PaperStatus.RECOMMENDED == "recommended"
    assert PaperStatus.STARRED == "starred"
    assert PaperStatus.SKIP == "skip"
    assert PaperStatus.ALL == {"pending", "recommended", "read", "starred", "skip"}


def test_paper_from_dict_json_authors():
    """from_dict handles authors stored as a JSON string."""
    paper = Paper.from_dict({
        "id": "W1",
        "title": "Test",
        "authors": '["Alice", "Bob"]',
        "venue": "CAV",
        "publication_date": "2024-01-01",
        "publication_year": 2024,
        "cited_by_count": 0,
        "score": 0.0,
        "track": "SMT",
        "tier": 0,
        "landing_page_url": "",
        "abstract": "",
    })
    assert paper.authors == ["Alice", "Bob"]


def test_paper_from_dict_invalid_json_authors():
    """from_dict falls back to single-item list on invalid JSON."""
    paper = Paper.from_dict({
        "id": "W1",
        "title": "Test",
        "authors": "Alice, Bob",
        "venue": "CAV",
        "publication_date": "2024-01-01",
        "publication_year": 2024,
        "cited_by_count": 0,
        "score": 0.0,
        "track": "SMT",
        "tier": 0,
        "landing_page_url": "",
        "abstract": "",
    })
    assert paper.authors == ["Alice, Bob"]


def test_paper_from_dict_string_tier():
    """from_dict coerces string tier to int."""
    paper = Paper.from_dict({
        "id": "W1",
        "title": "Test",
        "authors": [],
        "venue": "CAV",
        "publication_date": "2024-01-01",
        "publication_year": 2024,
        "cited_by_count": 0,
        "score": 0.0,
        "track": "SMT",
        "tier": "2",
        "landing_page_url": "",
        "abstract": "",
    })
    assert paper.tier == 2


def test_paper_from_dict_invalid_tier():
    """from_dict defaults tier to 0 on invalid value."""
    paper = Paper.from_dict({
        "id": "W1",
        "title": "Test",
        "authors": [],
        "venue": "CAV",
        "publication_date": "2024-01-01",
        "publication_year": 2024,
        "cited_by_count": 0,
        "score": 0.0,
        "track": "SMT",
        "tier": "invalid",
        "landing_page_url": "",
        "abstract": "",
    })
    assert paper.tier == 0


def test_paper_from_dict_missing_fields():
    """from_dict uses sensible defaults for missing fields."""
    paper = Paper.from_dict({"id": "W1"})
    assert paper.title == ""
    assert paper.authors == []
    assert paper.tier == 0
    assert paper.score == 0.0
    assert paper.status == "pending"


def test_paper_to_dict_roundtrip():
    """to_dict produces data that from_dict can reconstruct."""
    original = Paper(
        id="W1",
        title="Test Paper",
        authors=["Alice", "Bob"],
        venue="CAV",
        publication_date="2024-01-01",
        publication_year=2024,
        cited_by_count=10,
        score=5.0,
        track="SMT",
        tier=1,
        landing_page_url="https://example.com",
        abstract="An abstract.",
    )
    d = original.to_dict()
    restored = Paper.from_dict(d)
    assert restored.id == original.id
    assert restored.title == original.title
    assert restored.authors == original.authors
    assert restored.score == original.score
    assert restored.tier == original.tier


def test_paper_author_str():
    """author_str joins first 3 names and adds et al. when needed."""
    p1 = Paper(authors=["A", "B"])
    assert p1.author_str == "A, B"

    p2 = Paper(authors=["A", "B", "C", "D"])
    assert p2.author_str == "A, B, C, et al."

    p3 = Paper(authors=[])
    assert p3.author_str == ""


def test_paper_url_preference():
    """url prefers landing_page_url, then doi, then id."""
    p1 = Paper(landing_page_url="https://example.com", doi="10.1000/x", id="W1")
    assert p1.url == "https://example.com"

    p2 = Paper(landing_page_url="", doi="10.1000/x", id="W1")
    assert p2.url == "10.1000/x"

    p3 = Paper(landing_page_url="", doi=None, id="W1")
    assert p3.url == "W1"


def test_paper_year_or_date():
    """year_or_date prefers publication_date, then year, then ?."""
    p1 = Paper(publication_date="2024-01-15", publication_year=2024)
    assert p1.year_or_date == "2024-01-15"

    p2 = Paper(publication_date="", publication_year=2023)
    assert p2.year_or_date == "2023"

    p3 = Paper(publication_date="", publication_year=None)
    assert p3.year_or_date == "?"

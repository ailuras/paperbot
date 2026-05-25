"""Tests for email generation."""

from __future__ import annotations

from paperbot.mail import _build_email_body, _paper_to_html


def test_paper_to_html_contains_title():
    """HTML snippet contains paper title."""
    paper = {
        "title": "Test Paper",
        "authors": ["Alice", "Bob"],
        "venue": "CAV",
        "publication_date": "2024-01-01",
        "publication_year": 2024,
        "cited_by_count": 10,
        "score": 5.0,
        "track": "SMT",
        "tier": 1,
        "landing_page_url": "https://example.com",
        "abstract": "This is the abstract.",
    }
    html = _paper_to_html(paper, 1)
    assert "Test Paper" in html
    assert "Alice, Bob" in html
    assert "CAV" in html
    assert "https://example.com" in html
    assert "This is the abstract." in html


def test_paper_to_html_string_authors():
    """HTML handles authors stored as JSON string."""
    paper = {
        "title": "Test",
        "authors": '["Alice", "Bob"]',
        "venue": "CAV",
        "publication_date": "2024-01-01",
        "publication_year": 2024,
        "cited_by_count": 0,
        "score": 0,
        "track": "SMT",
        "tier": 0,
        "landing_page_url": "",
        "abstract": "",
    }
    html = _paper_to_html(paper, 1)
    assert "Alice, Bob" in html


def test_build_email_body_structure():
    """Email body is valid HTML with title and stats."""
    papers = [
        {
            "title": "Paper One",
            "authors": ["A"],
            "venue": "CAV",
            "publication_date": "2024-01-01",
            "publication_year": 2024,
            "cited_by_count": 5,
            "score": 5.0,
            "track": "SMT",
            "tier": 1,
            "landing_page_url": "https://example.com/1",
            "abstract": "Abstract one.",
        },
    ]
    stats = {"total_papers": 10, "pending": 5, "read": 3, "starred": 2}
    html = _build_email_body(
        papers, "Daily Recommendations", "2024-01-15", stats,
        dashboard_url="http://localhost:8765",
    )
    assert "<!DOCTYPE html>" in html
    assert "Paper One" in html
    assert "Daily Recommendations" in html
    assert "2024-01-15" in html
    assert "Total: 10" in html
    assert "Open Dashboard" in html



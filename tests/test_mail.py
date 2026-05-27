"""Tests for email generation."""

from __future__ import annotations

from paperbot.config import MailConfig, Settings, TrackConfig
from paperbot.mail import _build_email_body, _paper_to_html, _smtp_config
from paperbot.models import Paper


def test_paper_to_html_contains_title():
    """HTML snippet contains paper title."""
    paper = Paper(
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
        abstract="This is the abstract.",
    )
    html = _paper_to_html(paper, 1)
    assert "Test Paper" in html
    assert "Alice, Bob" in html
    assert "CAV" in html
    assert "https://example.com" in html
    assert "This is the abstract." in html


def test_paper_to_html_string_authors():
    """HTML handles authors stored as JSON string via from_dict."""
    paper = Paper.from_dict({
        "id": "W1",
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
    })
    html = _paper_to_html(paper, 1)
    assert "Alice, Bob" in html


def test_build_email_body_structure():
    """Email body is valid HTML with title and stats."""
    papers = [
        Paper(
            id="W1",
            title="Paper One",
            authors=["A"],
            venue="CAV",
            publication_date="2024-01-01",
            publication_year=2024,
            cited_by_count=5,
            score=5.0,
            track="SMT",
            tier=1,
            landing_page_url="https://example.com/1",
            abstract="Abstract one.",
        ),
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


def test_paper_to_html_escapes_untrusted_fields():
    """External paper and translation fields are escaped in email HTML."""
    paper = Paper(
        id="https://openalex.org/W1",
        title="<script>alert(1)</script>",
        authors=["Alice <img>"],
        venue="<b>CAV</b>",
        publication_date="2024-01-01",
        publication_year=2024,
        cited_by_count=10,
        score=5.0,
        track='SMT"><script>',
        tier=1,
        landing_page_url="javascript:alert(1)",
        abstract="<b>abstract</b>",
    )
    html = _paper_to_html(
        paper,
        1,
        {"title_zh": "<img src=x>", "abstract_zh": "<script>x</script>"},
    )

    assert "<script>" not in html
    assert "javascript:" not in html
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in html
    assert "&lt;b&gt;abstract&lt;/b&gt;" in html
    assert 'href="https://openalex.org/W1"' in html


def test_build_email_body_filters_dashboard_url():
    """Email dashboard link only renders safe HTTP URLs."""
    html = _build_email_body([], "Title", "2024-01-15", dashboard_url="javascript:alert(1)")
    assert "javascript:" not in html
    assert "Open Dashboard" in html


def test_smtp_env_overrides_config(monkeypatch):
    """SMTP env vars take precedence over config values."""
    settings = Settings(
        tracks={"SMT": TrackConfig(query="q", keywords=["k"])},
        scoring={
            "tiers": {"1": {"points": 5, "acronyms": ["CAV"], "phrases": []}},
            "citation_breakpoints": [{"up_to": None, "points_per_citation": 0.1}],
        },
        mail=MailConfig(
            smtp_host="config-host",
            smtp_port=2525,
            smtp_user="config-user",
            smtp_password="config-pass",
            from_addr="config@example.com",
        ),
    )
    monkeypatch.setenv("SMTP_HOST", "env-host")
    monkeypatch.setenv("SMTP_PORT", "1025")
    monkeypatch.setenv("SMTP_USER", "env-user")
    monkeypatch.setenv("SMTP_PASSWORD", "env-pass")
    monkeypatch.setenv("SMTP_FROM", "env@example.com")

    cfg = _smtp_config(settings)

    assert cfg["host"] == "env-host"
    assert cfg["port"] == 1025
    assert cfg["user"] == "env-user"
    assert cfg["password"] == "env-pass"
    assert cfg["from_addr"] == "env@example.com"


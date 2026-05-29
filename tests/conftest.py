"""Shared pytest fixtures for PaperBot tests."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from paperbot.db import init_db
from paperbot.models import Paper


@pytest.fixture
def sample_config_dict():
    """Minimal valid config dict for testing."""
    return {
        "tracks": {
            "SMT": {"query": "smt solver", "keywords": ["smt", "solver"]},
            "SAT": {"query": "sat solver", "keywords": ["sat", "solver"]},
        },
        "scoring": {
            "tiers": {
                "1": {"points": 5, "venues": {"CAV": []}},
                "2": {"points": 3, "venues": {"TACAS": []}},
            },
            "citation_breakpoints": [
                {"up_to": 10, "points_per_citation": 0.5},
                {"up_to": None, "points_per_citation": 0.1},
            ],
        },
    }


@pytest.fixture
def tmp_config_file(tmp_path: Path, sample_config_dict: dict):
    """Write sample config to a temporary file."""
    cfg_path = tmp_path / "config.json"
    cfg_path.write_text(json.dumps(sample_config_dict), encoding="utf-8")
    return cfg_path


@pytest.fixture
def tmp_db_path(tmp_path: Path) -> Path:
    """Create a temporary SQLite database, initialized with schema."""
    db_path = tmp_path / "test.db"
    init_db(db_path)
    return db_path


@pytest.fixture
def sample_paper():
    """Return a realistic Paper for reuse."""
    return Paper(
        id="https://openalex.org/W123456789",
        doi="10.1000/test.123",
        title="Test Paper on SMT Solvers",
        authors=["Alice Researcher", "Bob Scientist"],
        publication_year=2023,
        publication_date="2023-06-15",
        venue="Proceedings of CAV 2023",
        cited_by_count=42,
        abstract="This paper presents a novel approach to SMT solving.",
        landing_page_url="https://example.com/paper",
        pdf_url="https://example.com/paper.pdf",
        track="SMT",
        score=5.0,
        tier=1,
    )


@pytest.fixture
def sample_papers():
    """Return multiple Paper objects."""
    return [
        Paper(
            id="https://openalex.org/W1",
            title="Paper One",
            authors=["Author A"],
            publication_year=2024,
            publication_date="2024-01-15",
            venue="CAV 2024",
            cited_by_count=100,
            abstract="Abstract one.",
            landing_page_url="https://example.com/1",
            track="SMT",
            score=5.0,
            tier=1,
        ),
        Paper(
            id="https://openalex.org/W2",
            title="Paper Two",
            authors=["Author B", "Author C"],
            publication_year=2023,
            publication_date="2023-12-01",
            venue="TACAS 2023",
            cited_by_count=20,
            abstract="Abstract two.",
            landing_page_url="https://example.com/2",
            track="SAT",
            score=3.0,
            tier=2,
        ),
        Paper(
            id="https://openalex.org/W3",
            title="Paper Three",
            authors=["Author D"],
            publication_year=2024,
            publication_date="2024-02-20",
            venue="Some Workshop",
            cited_by_count=5,
            abstract="Abstract three.",
            landing_page_url="https://example.com/3",
            track="CP",
            score=0.0,
            tier=0,
        ),
    ]

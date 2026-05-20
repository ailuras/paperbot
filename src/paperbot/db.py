"""Database layer — SQLite + SQLAlchemy (placeholder)."""

from __future__ import annotations

from pathlib import Path

# Schema (target)
# ──────────────
# papers:
#   id TEXT PRIMARY KEY          -- OpenAlex ID
#   title TEXT NOT NULL
#   authors TEXT                 -- JSON list
#   venue TEXT
#   year INTEGER
#   abstract TEXT
#   url TEXT
#   openalex_json TEXT           -- raw JSON
#   fetched_at TEXT
#   track TEXT                   -- SMT|SAT|CP
#   score REAL DEFAULT 0
#   citation_count INTEGER DEFAULT 0
#
# recommendations:
#   id INTEGER PRIMARY KEY AUTOINCREMENT
#   date TEXT NOT NULL           -- YYYY-MM-DD
#   paper_id TEXT NOT NULL
#   slot_index INTEGER
#   reason TEXT
#
# marks:
#   paper_id TEXT PRIMARY KEY
#   status TEXT                  -- read|skip|later
#   marked_at TEXT
#   note TEXT


def init_db(db_path: Path) -> None:
    """Create tables if they don't exist."""
    pass


def insert_papers(papers: list[dict]) -> None:
    """Upsert papers into the database."""
    pass


def get_papers(track: str | None = None, unread_only: bool = False) -> list[dict]:
    """Query papers with optional filters."""
    return []


def save_recommendation(date: str, picks: list[dict]) -> None:
    """Persist a daily recommendation set."""
    pass


def get_recommendation_history(limit: int = 30) -> list[dict]:
    """Return past recommendations."""
    return []


def mark_paper(paper_id: str, status: str, note: str = "") -> None:
    """Mark a paper with a status."""
    pass


def get_stats() -> dict:
    """Return database statistics."""
    return {}

"""Tests for the SQLite database layer."""

from __future__ import annotations

from pathlib import Path

from paperbot.db import (
    get_paper_by_id_or_title,
    get_paper_note,
    get_recent_reads,
    get_stats,
    get_unread_papers,
    init_db,
    list_papers,
    save_recommendation,
    set_paper_note,
    set_paper_status,
    upsert_papers,
)


def test_init_db_creates_tables(tmp_path: Path):
    """init_db creates all required tables."""
    db_path = tmp_path / "fresh.db"
    init_db(db_path)
    import sqlite3

    conn = sqlite3.connect(db_path)
    tables = {
        row[0]
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        )
    }
    conn.close()
    assert "papers" in tables
    assert "recommendations" in tables
    assert "paper_states" in tables
    assert "paper_notes" in tables


def test_upsert_papers_insert(tmp_db_path: Path, sample_paper: dict):
    """upsert_papers inserts new papers and auto-marks pending."""
    inserted, updated = upsert_papers(tmp_db_path, [sample_paper])
    assert inserted == 1
    assert updated == 0

    stats = get_stats(tmp_db_path)
    assert stats["total_papers"] == 1
    assert stats["pending"] == 1


def test_upsert_papers_update(tmp_db_path: Path, sample_paper: dict):
    """upsert_papers updates existing papers."""
    upsert_papers(tmp_db_path, [sample_paper])
    modified = {**sample_paper, "title": "Updated Title"}
    inserted, updated = upsert_papers(tmp_db_path, [modified])
    assert inserted == 0
    assert updated == 1

    matches = get_paper_by_id_or_title(tmp_db_path, sample_paper["id"])
    assert matches[0]["title"] == "Updated Title"


def test_set_paper_status(tmp_db_path: Path, sample_paper: dict):
    """set_paper_status transitions work."""
    upsert_papers(tmp_db_path, [sample_paper])

    set_paper_status(tmp_db_path, sample_paper["id"], "read")
    stats = get_stats(tmp_db_path)
    assert stats["read"] == 1
    assert stats["pending"] == 0

    set_paper_status(tmp_db_path, sample_paper["id"], "starred")
    stats = get_stats(tmp_db_path)
    assert stats["starred"] == 1
    assert stats["read"] == 0


def test_get_unread_papers(tmp_db_path: Path, sample_papers: list):
    """get_unread_papers returns only pending papers."""
    upsert_papers(tmp_db_path, sample_papers)
    set_paper_status(tmp_db_path, sample_papers[0]["id"], "read")

    unread = get_unread_papers(tmp_db_path)
    assert len(unread) == 2
    ids = {p["id"] for p in unread}
    assert sample_papers[0]["id"] not in ids


def test_list_papers_filter_by_status(tmp_db_path: Path, sample_papers: list):
    """list_papers filters by status correctly."""
    upsert_papers(tmp_db_path, sample_papers)
    set_paper_status(tmp_db_path, sample_papers[0]["id"], "read")

    result = list_papers(tmp_db_path, status="pending")
    assert result["total"] == 2

    result = list_papers(tmp_db_path, status="read")
    assert result["total"] == 1


def test_list_papers_filter_by_track(tmp_db_path: Path, sample_papers: list):
    """list_papers filters by track."""
    upsert_papers(tmp_db_path, sample_papers)
    result = list_papers(tmp_db_path, track="SMT")
    assert result["total"] == 1
    assert result["papers"][0]["track"] == "SMT"


def test_list_papers_search_keyword(tmp_db_path: Path, sample_papers: list):
    """list_papers searches title and abstract."""
    upsert_papers(tmp_db_path, sample_papers)
    result = list_papers(tmp_db_path, keyword="Abstract two")
    assert result["total"] == 1
    assert result["papers"][0]["title"] == "Paper Two"


def test_list_papers_sort_and_pagination(tmp_db_path: Path, sample_papers: list):
    """list_papers supports sorting and pagination."""
    upsert_papers(tmp_db_path, sample_papers)

    by_score = list_papers(tmp_db_path, sort_by="score", limit=2)
    assert by_score["total"] == 3
    assert len(by_score["papers"]) == 2
    assert by_score["papers"][0]["score"] >= by_score["papers"][1]["score"]


def test_get_paper_by_id_or_title(tmp_db_path: Path, sample_paper: dict):
    """Search by exact ID and fuzzy title."""
    upsert_papers(tmp_db_path, [sample_paper])

    by_id = get_paper_by_id_or_title(tmp_db_path, sample_paper["id"])
    assert len(by_id) == 1

    by_title = get_paper_by_id_or_title(tmp_db_path, "SMT Solvers")
    assert len(by_title) == 1
    assert by_title[0]["title"] == sample_paper["title"]


def test_save_recommendation(tmp_db_path: Path, sample_papers: list):
    """save_recommendation persists daily picks."""
    upsert_papers(tmp_db_path, sample_papers)
    picks = [
        {"paper_id": p["id"], "slot_index": i}
        for i, p in enumerate(sample_papers[:2])
    ]
    save_recommendation(tmp_db_path, "2024-01-01", picks)

    stats = get_stats(tmp_db_path)
    assert stats["total_recommendations"] == 2


def test_get_recent_reads(tmp_db_path: Path, sample_papers: list):
    """get_recent_reads returns read papers ordered by changed_at."""
    upsert_papers(tmp_db_path, sample_papers)
    set_paper_status(tmp_db_path, sample_papers[0]["id"], "read")
    set_paper_status(tmp_db_path, sample_papers[1]["id"], "read")

    reads = get_recent_reads(tmp_db_path, limit=10)
    assert len(reads) == 2


def test_paper_notes(tmp_db_path: Path, sample_paper: dict):
    """get_paper_note and set_paper_note round-trip."""
    upsert_papers(tmp_db_path, [sample_paper])

    assert get_paper_note(tmp_db_path, sample_paper["id"]) == ""

    set_paper_note(tmp_db_path, sample_paper["id"], "Great paper!")
    assert get_paper_note(tmp_db_path, sample_paper["id"]) == "Great paper!"

    set_paper_note(tmp_db_path, sample_paper["id"], "Updated note.")
    assert get_paper_note(tmp_db_path, sample_paper["id"]) == "Updated note."


def test_get_stats_counts(tmp_db_path: Path, sample_papers: list):
    """get_stats returns accurate aggregated counts."""
    upsert_papers(tmp_db_path, sample_papers)
    set_paper_status(tmp_db_path, sample_papers[0]["id"], "read")
    set_paper_status(tmp_db_path, sample_papers[1]["id"], "starred")
    set_paper_status(tmp_db_path, sample_papers[2]["id"], "skip")

    stats = get_stats(tmp_db_path)
    assert stats["total_papers"] == 3
    assert stats["pending"] == 0
    assert stats["read"] == 1
    assert stats["starred"] == 1
    assert stats["skipped"] == 1
    assert stats["by_track"] == {"SMT": 1, "SAT": 1, "CP": 1}

"""Database layer — SQLite."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any

# ── Schema ──────────────────────────────────────────────────────────

_SCHEMA = """
CREATE TABLE IF NOT EXISTS papers (
    id TEXT PRIMARY KEY,
    doi TEXT,
    title TEXT NOT NULL,
    authors TEXT,
    publication_year INTEGER,
    publication_date TEXT,
    venue TEXT,
    cited_by_count INTEGER DEFAULT 0,
    abstract TEXT,
    landing_page_url TEXT,
    pdf_url TEXT,
    track TEXT,
    score REAL DEFAULT 0,
    tier TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS recommendations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    paper_id TEXT NOT NULL,
    slot_index INTEGER,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS paper_states (
    paper_id TEXT PRIMARY KEY,
    status TEXT NOT NULL DEFAULT 'pending',
    changed_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS paper_notes (
    paper_id TEXT PRIMARY KEY,
    note TEXT NOT NULL DEFAULT '',
    updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS paper_translations (
    paper_id TEXT PRIMARY KEY,
    title_zh TEXT,
    abstract_zh TEXT,
    updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS paper_pdfs (
    paper_id TEXT PRIMARY KEY,
    pdf_url TEXT NOT NULL,
    pdf_source TEXT,
    resolved_at TEXT DEFAULT (datetime('now'))
);
"""

# ── Connection helper ───────────────────────────────────────────────


def _connect(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


# ── Public API ──────────────────────────────────────────────────────


def init_db(db_path: Path) -> None:
    """Create tables if they don't exist."""
    conn = _connect(db_path)
    conn.executescript(_SCHEMA)
    conn.commit()
    conn.close()


def upsert_papers(
    db_path: Path,
    papers: list[dict[str, Any]],
) -> tuple[int, int]:
    """Bulk upsert papers. Returns (inserted, updated)."""
    conn = _connect(db_path)
    cursor = conn.cursor()

    inserted = 0
    updated = 0

    for paper in papers:
        paper_id = paper.get("id")
        if not paper_id:
            continue

        # Normalize authors to JSON string if it's a list
        authors = paper.get("authors")
        if isinstance(authors, list):
            authors = json.dumps(authors, ensure_ascii=False)

        # Convert tier to string if present
        tier = paper.get("tier")
        if tier is not None:
            tier = str(tier)

        row = (
            paper_id,
            paper.get("doi"),
            paper.get("title"),
            authors,
            paper.get("publication_year"),
            paper.get("publication_date"),
            paper.get("venue"),
            paper.get("cited_by_count", 0),
            paper.get("abstract"),
            paper.get("landing_page_url"),
            paper.get("pdf_url"),
            paper.get("track"),
            paper.get("score", 0.0),
            tier,
        )

        cursor.execute(
            """
            SELECT 1 FROM papers WHERE id = ?
            """,
            (paper_id,),
        )
        exists = cursor.fetchone() is not None

        if exists:
            cursor.execute(
                """
                UPDATE papers SET
                    doi = ?,
                    title = ?,
                    authors = ?,
                    publication_year = ?,
                    publication_date = ?,
                    venue = ?,
                    cited_by_count = ?,
                    abstract = ?,
                    landing_page_url = ?,
                    pdf_url = ?,
                    track = ?,
                    score = ?,
                    tier = ?,
                    updated_at = datetime('now')
                WHERE id = ?
                """,
                row[1:] + (paper_id,),
            )
            updated += 1
        else:
            cursor.execute(
                """
                INSERT INTO papers (
                    id, doi, title, authors, publication_year, publication_date,
                    venue, cited_by_count, abstract, landing_page_url, pdf_url,
                    track, score, tier
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                row,
            )
            # Auto-mark new papers as pending
            cursor.execute(
                """
                INSERT INTO paper_states (paper_id, status, changed_at)
                VALUES (?, 'pending', datetime('now'))
                ON CONFLICT(paper_id) DO NOTHING
                """,
                (paper_id,),
            )
            inserted += 1

    conn.commit()
    conn.close()
    return inserted, updated


def get_unread_papers(
    db_path: Path,
    track: str | None = None,
    limit: int | None = None,
    recent_days: int | None = None,
) -> list[dict[str, Any]]:
    """Query candidate papers for recommendation.

    Excludes papers that have been read or skipped.
    """
    conn = _connect(db_path)
    params: list[Any] = []

    sql = """
    SELECT p.* FROM papers p
    LEFT JOIN paper_states ps ON p.id = ps.paper_id
    WHERE ps.status = 'pending'
    """

    if recent_days is not None:
        sql += " AND p.publication_date >= date('now', '-{} days')".format(recent_days)

    if track:
        sql += " AND p.track LIKE ?"
        params.append(f"%{track}%")

    sql += " ORDER BY p.score DESC, p.cited_by_count DESC"

    if limit:
        sql += " LIMIT ?"
        params.append(limit)

    cursor = conn.execute(sql, params)
    rows = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return rows


def save_recommendation(
    db_path: Path,
    date: str,
    picks: list[dict[str, Any]],
) -> None:
    """Persist a daily recommendation set.

    picks: list of dicts with keys: paper_id, slot_index
    """
    conn = _connect(db_path)
    for pick in picks:
        conn.execute(
            """
            INSERT INTO recommendations (date, paper_id, slot_index)
            VALUES (?, ?, ?)
            """,
            (
                date,
                pick["paper_id"],
                pick.get("slot_index"),
            ),
        )
    conn.commit()
    conn.close()


def get_recommendation_history(
    db_path: Path,
    days: int = 7,
) -> list[dict[str, Any]]:
    """Return past recommendations grouped by date."""
    conn = _connect(db_path)
    cursor = conn.execute(
        """
        SELECT r.*, p.title, p.track, p.score
        FROM recommendations r
        JOIN papers p ON r.paper_id = p.id
        WHERE r.date >= date('now', '-{} days')
        ORDER BY r.date DESC, r.slot_index ASC
        """.format(days),
    )
    rows = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return rows


def get_recent_reads(
    db_path: Path,
    limit: int = 3,
) -> list[dict[str, Any]]:
    """Return most recently read papers with full details."""
    conn = _connect(db_path)
    cursor = conn.execute(
        """
        SELECT p.*, COALESCE(ps.status, 'pending') as status, ps.changed_at
        FROM papers p
        JOIN paper_states ps ON p.id = ps.paper_id
        WHERE ps.status = 'read'
        ORDER BY ps.changed_at DESC
        LIMIT ?
        """,
        (limit,),
    )
    rows = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return rows


def set_paper_status(
    db_path: Path,
    paper_id: str,
    status: str,
) -> None:
    """Mark a paper with a status (read, skip, starred, pending)."""
    conn = _connect(db_path)
    conn.execute(
        """
        INSERT INTO paper_states (paper_id, status, changed_at)
        VALUES (?, ?, datetime('now'))
        ON CONFLICT(paper_id) DO UPDATE SET
            status = excluded.status,
            changed_at = datetime('now')
        """,
        (paper_id, status),
    )
    conn.commit()
    conn.close()


def get_paper_by_id_or_title(
    db_path: Path,
    query: str,
    limit: int = 5,
) -> list[dict[str, Any]]:
    """Search papers by exact ID or fuzzy title match."""
    conn = _connect(db_path)

    # Try exact match first
    cursor = conn.execute("SELECT * FROM papers WHERE id = ? LIMIT 1", (query,))
    row = cursor.fetchone()
    if row:
        conn.close()
        return [dict(row)]

    # Fuzzy title search
    cursor = conn.execute(
        """
        SELECT * FROM papers
        WHERE title LIKE ?
        ORDER BY score DESC
        LIMIT ?
        """,
        (f"%{query}%", limit),
    )
    rows = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return rows


def list_papers(
    db_path: Path,
    track: str | None = None,
    status: str | None = None,
    keyword: str | None = None,
    sort_by: str = "score",
    sort_order: str = "desc",
    limit: int = 50,
    offset: int = 0,
) -> dict[str, Any]:
    """Return paginated paper list with optional filters and sorting."""
    conn = _connect(db_path)
    params: list[Any] = []

    where_clauses: list[str] = []

    if track:
        where_clauses.append("p.track LIKE ?")
        params.append(f"%{track}%")

    if status:
        if status == "pending":
            where_clauses.append("ps.status = 'pending'")
        elif status == "read":
            where_clauses.append("ps.status IN ('read', 'recommended')")
        else:
            where_clauses.append("ps.status = ?")
            params.append(status)

    if keyword:
        where_clauses.append("(p.title LIKE ? OR p.abstract LIKE ?)")
        params.append(f"%{keyword}%")
        params.append(f"%{keyword}%")

    where_sql = ""
    if where_clauses:
        where_sql = "WHERE " + " AND ".join(where_clauses)

    count_sql = f"""
    SELECT COUNT(*) FROM papers p
    LEFT JOIN paper_states ps ON p.id = ps.paper_id
    {where_sql}
    """
    total = conn.execute(count_sql, params).fetchone()[0]

    # Validate sort column
    valid_sort_cols = {"score", "cited_by_count", "publication_date", "created_at", "title", "changed_at"}
    sort_col = sort_by if sort_by in valid_sort_cols else "score"
    order = "DESC" if sort_order.lower() == "desc" else "ASC"

    # Determine sort column prefix (p.* vs ps.*)
    if sort_col == "changed_at":
        sort_prefix = "ps"
        secondary = "p.score DESC"
    else:
        sort_prefix = "p"
        secondary = "p.cited_by_count DESC" if sort_col == "score" else "p.score DESC"

    sql = f"""
    SELECT p.*, COALESCE(ps.status, 'pending') as status, ps.changed_at
    FROM papers p
    LEFT JOIN paper_states ps ON p.id = ps.paper_id
    {where_sql}
    ORDER BY {sort_prefix}.{sort_col} {order}, {secondary}
    LIMIT ? OFFSET ?
    """
    cursor = conn.execute(sql, params + [limit, offset])
    rows = [dict(row) for row in cursor.fetchall()]
    conn.close()

    return {"total": total, "papers": rows, "limit": limit, "offset": offset}


def get_paper_note(db_path: Path, paper_id: str) -> str:
    """Get note for a paper."""
    conn = _connect(db_path)
    cursor = conn.execute(
        "SELECT note FROM paper_notes WHERE paper_id = ?",
        (paper_id,),
    )
    row = cursor.fetchone()
    conn.close()
    return row[0] if row else ""


def set_paper_note(db_path: Path, paper_id: str, note: str) -> None:
    """Save or update note for a paper."""
    conn = _connect(db_path)
    conn.execute(
        """
        INSERT INTO paper_notes (paper_id, note, updated_at)
        VALUES (?, ?, datetime('now'))
        ON CONFLICT(paper_id) DO UPDATE SET
            note = excluded.note,
            updated_at = datetime('now')
        """,
        (paper_id, note),
    )
    conn.commit()
    conn.close()


def get_stats(db_path: Path) -> dict[str, Any]:
    """Return database statistics."""
    conn = _connect(db_path)
    stats: dict[str, Any] = {}

    row = conn.execute("SELECT COUNT(*) FROM papers").fetchone()
    stats["total_papers"] = row[0] if row else 0

    row = conn.execute("SELECT COUNT(*) FROM recommendations").fetchone()
    stats["total_recommendations"] = row[0] if row else 0

    row = conn.execute("SELECT COUNT(*) FROM paper_states").fetchone()
    stats["total_states"] = row[0] if row else 0

    cursor = conn.execute(
        "SELECT track, COUNT(*) FROM papers GROUP BY track"
    )
    stats["by_track"] = {row[0] or "unknown": row[1] for row in cursor}

    cursor = conn.execute(
        "SELECT status, COUNT(*) FROM paper_states GROUP BY status"
    )
    stats["by_status"] = {row[0] or "unknown": row[1] for row in cursor}

    row = conn.execute(
        """
        SELECT COUNT(DISTINCT date) FROM recommendations
        WHERE date >= date('now', '-7 days')
        """
    ).fetchone()
    stats["recommendations_last_7_days"] = row[0] if row else 0

    # Pending / read / starred counts (recommended merged into read)
    cursor = conn.execute(
        """
        SELECT
            COUNT(CASE WHEN ps.status = 'pending' THEN 1 END) as pending,
            COUNT(CASE WHEN ps.status IN ('read', 'recommended') THEN 1 END) as read,
            COUNT(CASE WHEN ps.status = 'starred' THEN 1 END) as starred,
            COUNT(CASE WHEN ps.status = 'skip' THEN 1 END) as skipped
        FROM papers p
        LEFT JOIN paper_states ps ON p.id = ps.paper_id
        """
    )
    row = cursor.fetchone()
    if row:
        stats["pending"] = row[0]
        stats["read"] = row[1]
        stats["starred"] = row[2]
        stats["skipped"] = row[3]

    conn.close()
    return stats


# ── Translation cache ─────────────────────────────────────────────────


def get_paper_translation(db_path: Path, paper_id: str) -> dict[str, str]:
    """Get cached translation for a paper."""
    conn = _connect(db_path)
    cursor = conn.execute(
        "SELECT title_zh, abstract_zh FROM paper_translations WHERE paper_id = ?",
        (paper_id,),
    )
    row = cursor.fetchone()
    conn.close()
    if row:
        return {"title_zh": row[0] or "", "abstract_zh": row[1] or ""}
    return {"title_zh": "", "abstract_zh": ""}


def set_paper_translation(
    db_path: Path,
    paper_id: str,
    title_zh: str,
    abstract_zh: str,
) -> None:
    """Save or update translation for a paper."""
    conn = _connect(db_path)
    conn.execute(
        """
        INSERT INTO paper_translations (paper_id, title_zh, abstract_zh, updated_at)
        VALUES (?, ?, ?, datetime('now'))
        ON CONFLICT(paper_id) DO UPDATE SET
            title_zh = excluded.title_zh,
            abstract_zh = excluded.abstract_zh,
            updated_at = datetime('now')
        """,
        (paper_id, title_zh, abstract_zh),
    )
    conn.commit()
    conn.close()


# ── PDF URL cache ─────────────────────────────────────────────────────


def get_paper_pdf(db_path: Path, paper_id: str) -> dict[str, str] | None:
    """Get cached PDF URL for a paper."""
    conn = _connect(db_path)
    cursor = conn.execute(
        "SELECT pdf_url, pdf_source FROM paper_pdfs WHERE paper_id = ?",
        (paper_id,),
    )
    row = cursor.fetchone()
    conn.close()
    if row:
        return {"pdf_url": row[0], "pdf_source": row[1] or ""}
    return None


def set_paper_pdf(
    db_path: Path,
    paper_id: str,
    pdf_url: str,
    pdf_source: str = "",
) -> None:
    """Save or update PDF URL for a paper."""
    conn = _connect(db_path)
    conn.execute(
        """
        INSERT INTO paper_pdfs (paper_id, pdf_url, pdf_source, resolved_at)
        VALUES (?, ?, ?, datetime('now'))
        ON CONFLICT(paper_id) DO UPDATE SET
            pdf_url = excluded.pdf_url,
            pdf_source = excluded.pdf_source,
            resolved_at = datetime('now')
        """,
        (paper_id, pdf_url, pdf_source),
    )
    conn.commit()
    conn.close()

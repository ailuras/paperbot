"""Database layer — SQLite."""

from __future__ import annotations

import json
import sqlite3
from contextlib import closing
from pathlib import Path
from typing import Any

from paperbot.models import Paper

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
    venue_abbr TEXT,
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
    with closing(_connect(db_path)) as conn:
        conn.executescript(_SCHEMA)
        # Migrate: add venue_abbr if missing
        cols = {
            r[1]
            for r in conn.execute("PRAGMA table_info(papers)")
        }
        if "venue_abbr" not in cols:
            conn.execute("ALTER TABLE papers ADD COLUMN venue_abbr TEXT")
        conn.commit()


def upsert_papers(
    db_path: Path,
    papers: list[Paper],
) -> tuple[int, int]:
    """Bulk upsert papers. Returns (inserted, updated)."""
    inserted = 0
    updated = 0

    with closing(_connect(db_path)) as conn:
        cursor = conn.cursor()

        for paper in papers:
            paper_id = paper.id
            if not paper_id:
                continue

            # Normalize authors to JSON string for storage
            authors_json = json.dumps(paper.authors, ensure_ascii=False) if paper.authors else None

            row = (
                paper_id,
                paper.doi,
                paper.title,
                authors_json,
                paper.publication_year,
                paper.publication_date,
                paper.venue,
                paper.venue_abbr,
                paper.cited_by_count,
                paper.abstract,
                paper.landing_page_url,
                paper.pdf_url,
                paper.track,
                paper.score,
                str(paper.tier) if paper.tier is not None else None,
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
                        venue_abbr = ?,
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
                        venue, venue_abbr, cited_by_count, abstract, landing_page_url, pdf_url,
                        track, score, tier
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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

    return inserted, updated


def get_unread_papers(
    db_path: Path,
    track: str | None = None,
    limit: int | None = None,
    recent_days: int | None = None,
) -> list[Paper]:
    """Query candidate papers for recommendation.

    Excludes papers that have been read or skipped.
    """
    params: list[Any] = []

    sql = """
    SELECT p.* FROM papers p
    LEFT JOIN paper_states ps ON p.id = ps.paper_id
    WHERE ps.status = 'pending'
    """

    if recent_days is not None:
        sql += " AND p.publication_date >= date('now', ?)"
        params.append(f"-{recent_days} days")

    if track:
        sql += " AND p.track LIKE ?"
        params.append(f"%{track}%")

    sql += " ORDER BY p.score DESC, p.cited_by_count DESC"

    if limit:
        sql += " LIMIT ?"
        params.append(limit)

    with closing(_connect(db_path)) as conn:
        cursor = conn.execute(sql, params)
        papers = [Paper.from_dict(dict(row)) for row in cursor.fetchall()]

    return papers


def save_recommendation(
    db_path: Path,
    date: str,
    picks: list[dict[str, Any]],
) -> None:
    """Persist a daily recommendation set.

    picks: list of dicts with keys: paper_id, slot_index
    """
    with closing(_connect(db_path)) as conn:
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


def get_recommendation_history(
    db_path: Path,
    days: int = 7,
) -> list[dict[str, Any]]:
    """Return past recommendations grouped by date."""
    with closing(_connect(db_path)) as conn:
        cursor = conn.execute(
            """
            SELECT r.*, p.title, p.track, p.score
            FROM recommendations r
            JOIN papers p ON r.paper_id = p.id
            WHERE r.date >= date('now', ?)
            ORDER BY r.date DESC, r.slot_index ASC
            """,
            (f"-{days} days",),
        )
        rows = [dict(row) for row in cursor.fetchall()]

    return rows


def get_recent_reads(
    db_path: Path,
    limit: int = 3,
    status: str = "read",
) -> list[Paper]:
    """Return most recently marked papers with full details."""
    with closing(_connect(db_path)) as conn:
        cursor = conn.execute(
            """
            SELECT p.*, COALESCE(ps.status, 'pending') as status, ps.changed_at
            FROM papers p
            JOIN paper_states ps ON p.id = ps.paper_id
            WHERE ps.status = ?
            ORDER BY ps.changed_at DESC
            LIMIT ?
            """,
            (status, limit),
        )
        papers = [Paper.from_dict(dict(row)) for row in cursor.fetchall()]

    return papers


def set_paper_status(
    db_path: Path,
    paper_id: str,
    status: str,
) -> None:
    """Mark a paper with a status (read, skip, starred, pending)."""
    with closing(_connect(db_path)) as conn:
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


def get_paper_by_id_or_title(
    db_path: Path,
    query: str,
    limit: int = 5,
) -> list[Paper]:
    """Search papers by exact ID or fuzzy title match."""
    with closing(_connect(db_path)) as conn:
        # Try exact match first
        cursor = conn.execute("SELECT * FROM papers WHERE id = ? LIMIT 1", (query,))
        row = cursor.fetchone()
        if row:
            return [Paper.from_dict(dict(row))]

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
        papers = [Paper.from_dict(dict(row)) for row in cursor.fetchall()]

    return papers


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
    params: list[Any] = []

    where_clauses: list[str] = []

    if track:
        where_clauses.append("p.track LIKE ?")
        params.append(f"%{track}%")

    if status:
        if status == "pending":
            where_clauses.append("ps.status = 'pending'")
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

    with closing(_connect(db_path)) as conn:
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
        papers = [Paper.from_dict(dict(row)) for row in cursor.fetchall()]

    return {"total": total, "papers": papers, "limit": limit, "offset": offset}


def get_paper_note(db_path: Path, paper_id: str) -> str:
    """Get note for a paper."""
    with closing(_connect(db_path)) as conn:
        cursor = conn.execute(
            "SELECT note FROM paper_notes WHERE paper_id = ?",
            (paper_id,),
        )
        row = cursor.fetchone()
        return row[0] if row else ""


def set_paper_note(db_path: Path, paper_id: str, note: str) -> None:
    """Save or update note for a paper."""
    with closing(_connect(db_path)) as conn:
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


def get_stats(db_path: Path) -> dict[str, Any]:
    """Return database statistics."""
    stats: dict[str, Any] = {}

    with closing(_connect(db_path)) as conn:
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

        # Pending / recommended / read / starred counts are tracked separately.
        cursor = conn.execute(
            """
            SELECT
                COUNT(CASE WHEN ps.status = 'pending' THEN 1 END) as pending,
                COUNT(CASE WHEN ps.status = 'recommended' THEN 1 END) as recommended,
                COUNT(CASE WHEN ps.status = 'read' THEN 1 END) as read,
                COUNT(CASE WHEN ps.status = 'starred' THEN 1 END) as starred,
                COUNT(CASE WHEN ps.status = 'skip' THEN 1 END) as skipped
            FROM papers p
            LEFT JOIN paper_states ps ON p.id = ps.paper_id
            """
        )
        row = cursor.fetchone()
        if row:
            stats["pending"] = row[0]
            stats["recommended"] = row[1]
            stats["read"] = row[2]
            stats["starred"] = row[3]
            stats["skipped"] = row[4]

    return stats


# ── Translation cache ─────────────────────────────────────────────────


def get_paper_translation(db_path: Path, paper_id: str) -> dict[str, str]:
    """Get cached translation for a paper."""
    with closing(_connect(db_path)) as conn:
        cursor = conn.execute(
            "SELECT title_zh, abstract_zh FROM paper_translations WHERE paper_id = ?",
            (paper_id,),
        )
        row = cursor.fetchone()
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
    with closing(_connect(db_path)) as conn:
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


# ── PDF URL cache ─────────────────────────────────────────────────────


def get_paper_pdf(db_path: Path, paper_id: str) -> dict[str, str] | None:
    """Get cached PDF URL for a paper."""
    with closing(_connect(db_path)) as conn:
        cursor = conn.execute(
            "SELECT pdf_url, pdf_source FROM paper_pdfs WHERE paper_id = ?",
            (paper_id,),
        )
        row = cursor.fetchone()
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
    with closing(_connect(db_path)) as conn:
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

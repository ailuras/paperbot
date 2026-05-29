"""Update helpers for refreshing stored PaperBot metadata."""

from __future__ import annotations

from contextlib import closing
from pathlib import Path
from typing import Any

from paperbot.config import Settings
from paperbot.db import _connect
from paperbot.fetch import VenueScorer
from paperbot.utils import compute_venue_abbr


def _coerce_tier(value: Any) -> int:
    try:
        return int(value) if value is not None else 0
    except (TypeError, ValueError):
        return 0


def _coerce_score(value: Any) -> float:
    try:
        return float(value) if value is not None else 0.0
    except (TypeError, ValueError):
        return 0.0


def refresh_existing_papers(db_path: Path, settings: Settings) -> dict[str, int]:
    """Recompute local derived fields for all stored papers.

    This updates only fields derived from existing local metadata and current
    config: venue abbreviation, venue tier, and score.
    """
    scorer = VenueScorer(settings)
    total = 0
    updated = 0

    with closing(_connect(db_path)) as conn:
        rows = conn.execute(
            """
            SELECT id, venue, cited_by_count, venue_abbr, score, tier
            FROM papers
            """
        ).fetchall()
        total = len(rows)

        for row in rows:
            venue = row["venue"] or ""
            citations = row["cited_by_count"] or 0
            new_abbr = compute_venue_abbr(venue)
            new_tier = scorer.get_tier(venue)
            new_score = scorer.calculate_score(venue, citations)

            old_abbr = row["venue_abbr"] or ""
            old_tier = _coerce_tier(row["tier"])
            old_score = _coerce_score(row["score"])

            if (
                old_abbr == new_abbr
                and old_tier == new_tier
                and abs(old_score - new_score) < 1e-9
            ):
                continue

            conn.execute(
                """
                UPDATE papers SET
                    venue_abbr = ?,
                    score = ?,
                    tier = ?,
                    updated_at = datetime('now')
                WHERE id = ?
                """,
                (new_abbr, new_score, str(new_tier), row["id"]),
            )
            updated += 1

        conn.commit()

    return {"total": total, "updated": updated}


def reset_paper_states(db_path: Path) -> int:
    """Reset every stored paper to pending, creating missing state rows."""
    with closing(_connect(db_path)) as conn:
        paper_ids = [row["id"] for row in conn.execute("SELECT id FROM papers")]
        for paper_id in paper_ids:
            conn.execute(
                """
                INSERT INTO paper_states (paper_id, status, changed_at)
                VALUES (?, 'pending', datetime('now'))
                ON CONFLICT(paper_id) DO UPDATE SET
                    status = 'pending',
                    changed_at = datetime('now')
                """,
                (paper_id,),
            )
        conn.commit()
    return len(paper_ids)

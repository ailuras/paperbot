#!/usr/bin/env python3
"""One-time script: backfill venue_abbr for existing papers."""

from pathlib import Path

from paperbot.config import default_config_path, load_config
from paperbot.db import _connect
from paperbot.utils import compute_venue_abbr


def main():
    cfg = load_config(default_config_path())
    db_path = cfg.data_dir / "paperbot.db"

    if not db_path.exists():
        print(f"Database not found: {db_path}")
        return

    conn = _connect(db_path)
    cursor = conn.cursor()

    # Ensure column exists
    cols = {r[1] for r in cursor.execute("PRAGMA table_info(papers)")}
    if "venue_abbr" not in cols:
        cursor.execute("ALTER TABLE papers ADD COLUMN venue_abbr TEXT")
        print("Added venue_abbr column")

    # Backfill
    rows = cursor.execute("SELECT id, venue FROM papers WHERE venue_abbr IS NULL OR venue_abbr = ''").fetchall()
    updated = 0
    for paper_id, venue in rows:
        abbr = compute_venue_abbr(venue)
        cursor.execute("UPDATE papers SET venue_abbr = ? WHERE id = ?", (abbr, paper_id))
        updated += 1

    conn.commit()
    conn.close()

    print(f"Updated {updated} papers")


if __name__ == "__main__":
    main()

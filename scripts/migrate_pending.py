"""One-time migration: backfill paper_states for existing papers without status."""

from pathlib import Path
import sqlite3
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from paperbot.config import load_config, default_config_path


def main() -> None:
    cfg = load_config(default_config_path())
    db_path = cfg.data_dir / "paperbot.db"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Find papers without a state record
    cursor.execute("""
        SELECT p.id FROM papers p
        LEFT JOIN paper_states ps ON p.id = ps.paper_id
        WHERE ps.paper_id IS NULL
    """)
    missing = [row[0] for row in cursor.fetchall()]

    if not missing:
        print("All papers already have a status record. Nothing to do.")
        conn.close()
        return

    print(f"Found {len(missing)} papers without status. Backfilling as 'pending'...")

    for paper_id in missing:
        cursor.execute(
            """
            INSERT INTO paper_states (paper_id, status, changed_at)
            VALUES (?, 'pending', datetime('now'))
            """,
            (paper_id,),
        )

    conn.commit()

    # Verify
    cursor.execute("SELECT COUNT(*) FROM paper_states WHERE status = 'pending'")
    pending_count = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM papers")
    total_count = cursor.fetchone()[0]

    print(f"Done. Total papers: {total_count}, Pending: {pending_count}")
    conn.close()


if __name__ == "__main__":
    main()

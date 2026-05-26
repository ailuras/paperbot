"""Audit logging — record all operations to DB and optionally to file."""

from __future__ import annotations

import json
import logging
import time
from contextlib import closing
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

from paperbot.db import _connect


# ── Database schema ───────────────────────────────────────────────────

_AUDIT_SCHEMA = """
CREATE TABLE IF NOT EXISTS audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT DEFAULT (datetime('now')),
    action TEXT NOT NULL,
    target_id TEXT,
    details TEXT,
    status TEXT,
    error_message TEXT,
    duration_ms INTEGER
);

CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_logs(timestamp);
"""


@dataclass
class AuditEntry:
    action: str
    target_id: str = ""
    details: dict[str, Any] = field(default_factory=dict)
    status: str = "success"
    error_message: str = ""
    duration_ms: int = 0


def init_audit(db_path: Path) -> None:
    """Create audit log tables if they don't exist."""
    with closing(_connect(db_path)) as conn:
        conn.executescript(_AUDIT_SCHEMA)
        conn.commit()


def log_audit(
    db_path: Path,
    entry: AuditEntry,
) -> int:
    """Write an audit entry to the database."""
    with closing(_connect(db_path)) as conn:
        cursor = conn.execute(
            """
            INSERT INTO audit_logs (action, target_id, details, status, error_message, duration_ms)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                entry.action,
                entry.target_id,
                json.dumps(entry.details, ensure_ascii=False) if entry.details else None,
                entry.status,
                entry.error_message or None,
                entry.duration_ms,
            ),
        )
        conn.commit()
        row_id = cursor.lastrowid or 0

    return row_id


def get_audit_logs(
    db_path: Path,
    action: str | None = None,
    limit: int = 100,
    offset: int = 0,
) -> list[dict[str, Any]]:
    """Query audit logs with optional filtering."""
    params: list[Any] = []
    sql = "SELECT * FROM audit_logs"
    if action:
        sql += " WHERE action = ?"
        params.append(action)
    sql += " ORDER BY timestamp DESC LIMIT ? OFFSET ?"
    params.extend([limit, offset])

    with closing(_connect(db_path)) as conn:
        cursor = conn.execute(sql, params)
        rows = []
        for row in cursor:
            d = dict(row)
            if d.get("details"):
                try:
                    d["details"] = json.loads(d["details"])
                except json.JSONDecodeError:
                    pass
            rows.append(d)

    return rows


def get_audit_stats(db_path: Path, days: int = 7) -> dict[str, Any]:
    """Return audit statistics for the last N days."""
    with closing(_connect(db_path)) as conn:
        total = conn.execute(
            "SELECT COUNT(*) FROM audit_logs WHERE timestamp >= date('now', ?)",
            (f"-{days} days",),
        ).fetchone()[0]

        cursor = conn.execute(
            """
            SELECT action, status, COUNT(*)
            FROM audit_logs
            WHERE timestamp >= date('now', ?)
            GROUP BY action, status
            """,
            (f"-{days} days",),
        )
        by_action = {}
        for row in cursor:
            action, status, count = row
            if action not in by_action:
                by_action[action] = {}
            by_action[action][status] = count

    return {"total": total, "by_action": by_action}


# ── Text file logging ─────────────────────────────────────────────────


def _file_log_path(data_dir: Path) -> Path:
    return data_dir / "audit.log"


def log_to_file(data_dir: Path, entry: AuditEntry) -> None:
    """Append a human-readable entry to the audit text log."""
    path = _file_log_path(data_dir)
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    status_icon = "✓" if entry.status == "success" else "✗" if entry.status == "error" else "→"
    line = (
        f"[{ts}] {status_icon} {entry.action}"
        f"{f' #{entry.target_id}' if entry.target_id else ''}"
        f" ({entry.duration_ms}ms)"
    )
    if entry.error_message:
        line += f" | ERROR: {entry.error_message}"
    if entry.details:
        detail_str = " | ".join(f"{k}={v}" for k, v in entry.details.items() if v is not None)
        if detail_str:
            line += f" | {detail_str}"
    line += "\n"

    with path.open("a", encoding="utf-8") as f:
        f.write(line)


# ── Decorator for easy instrumentation ────────────────────────────────


def audit(
    db_path: Path,
    data_dir: Path | None = None,
    action: str = "",
    target_id_attr: str = "",
):
    """Decorator to auto-log a function's execution.

    Usage:
        @audit(db_path, action="recommend")
        def do_recommend(...) -> ...:
            ...
    """

    def decorator(func):
        def wrapper(*args, **kwargs):
            start = time.time()
            entry = AuditEntry(action=action or func.__name__)

            # Try to extract target_id from kwargs
            if target_id_attr and target_id_attr in kwargs:
                entry.target_id = str(kwargs[target_id_attr])

            try:
                result = func(*args, **kwargs)
                entry.status = "success"
                # Capture return value as detail if it's a simple type
                if isinstance(result, (int, float, str, bool)):
                    entry.details["result"] = result
                return result
            except Exception as e:
                entry.status = "error"
                entry.error_message = str(e)
                raise
            finally:
                entry.duration_ms = int((time.time() - start) * 1000)
                try:
                    log_audit(db_path, entry)
                    if data_dir:
                        log_to_file(data_dir, entry)
                except Exception as exc:
                    logging.getLogger(__name__).warning("Audit logging failed: %s", exc)

        return wrapper

    return decorator

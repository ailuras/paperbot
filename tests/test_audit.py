"""Tests for the audit logging module."""

from __future__ import annotations

from pathlib import Path

from paperbot.audit import (
    AuditEntry,
    get_audit_logs,
    get_audit_stats,
    init_audit,
    log_audit,
    log_to_file,
)
from paperbot.db import init_db


def test_init_audit_creates_table(tmp_path: Path):
    """init_audit creates the audit_logs table and indexes."""
    db_path = tmp_path / "audit.db"
    init_db(db_path)
    init_audit(db_path)

    import sqlite3

    conn = sqlite3.connect(db_path)
    tables = {
        row[0]
        for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
    }
    indexes = {
        row[0]
        for row in conn.execute("SELECT name FROM sqlite_master WHERE type='index'")
    }
    conn.close()

    assert "audit_logs" in tables
    assert "idx_audit_action" in indexes
    assert "idx_audit_timestamp" in indexes


def test_log_audit_inserts_entry(tmp_db_path: Path):
    """log_audit writes an entry and returns its row id."""
    init_audit(tmp_db_path)
    entry = AuditEntry(
        action="fetch",
        target_id="W123",
        details={"count": 5},
        status="success",
        duration_ms=1234,
    )
    row_id = log_audit(tmp_db_path, entry)
    assert row_id > 0


def test_get_audit_logs_returns_entries(tmp_db_path: Path):
    """get_audit_logs returns inserted entries."""
    init_audit(tmp_db_path)
    log_audit(tmp_db_path, AuditEntry(action="fetch", status="success"))
    log_audit(tmp_db_path, AuditEntry(action="recommend", status="success"))

    logs = get_audit_logs(tmp_db_path, limit=10)
    assert len(logs) == 2
    assert logs[0]["action"] == "recommend"  # DESC order
    assert logs[1]["action"] == "fetch"


def test_get_audit_logs_filter_by_action(tmp_db_path: Path):
    """get_audit_logs filters by action."""
    init_audit(tmp_db_path)
    log_audit(tmp_db_path, AuditEntry(action="fetch"))
    log_audit(tmp_db_path, AuditEntry(action="recommend"))

    logs = get_audit_logs(tmp_db_path, action="fetch", limit=10)
    assert len(logs) == 1
    assert logs[0]["action"] == "fetch"


def test_get_audit_logs_details_roundtrip(tmp_db_path: Path):
    """Details dict is serialized and deserialized correctly."""
    init_audit(tmp_db_path)
    log_audit(
        tmp_db_path,
        AuditEntry(action="fetch", details={"total": 42, "range": "2024-01-01"}),
    )

    logs = get_audit_logs(tmp_db_path, limit=10)
    assert len(logs) == 1
    assert logs[0]["details"] == {"total": 42, "range": "2024-01-01"}


def test_get_audit_stats_aggregates(tmp_db_path: Path):
    """get_audit_stats aggregates by action and status."""
    init_audit(tmp_db_path)
    log_audit(tmp_db_path, AuditEntry(action="fetch", status="success"))
    log_audit(tmp_db_path, AuditEntry(action="fetch", status="success"))
    log_audit(tmp_db_path, AuditEntry(action="recommend", status="error"))

    stats = get_audit_stats(tmp_db_path, days=7)
    assert stats["total"] == 3
    assert stats["by_action"]["fetch"]["success"] == 2
    assert stats["by_action"]["recommend"]["error"] == 1


def test_log_to_file_writes_text(tmp_path: Path):
    """log_to_file appends a human-readable line."""
    data_dir = tmp_path / "data"
    data_dir.mkdir()
    entry = AuditEntry(
        action="fetch",
        target_id="W123",
        status="success",
        duration_ms=100,
        details={"count": 5},
    )
    log_to_file(data_dir, entry)

    log_path = data_dir / "audit.log"
    assert log_path.exists()
    content = log_path.read_text(encoding="utf-8")
    assert "fetch" in content
    assert "W123" in content
    assert "100ms" in content
    assert "count=5" in content


def test_log_to_file_error_entry(tmp_path: Path):
    """log_to_file includes error message for error entries."""
    data_dir = tmp_path / "data"
    data_dir.mkdir()
    entry = AuditEntry(
        action="recommend",
        status="error",
        error_message="email_failed",
        duration_ms=50,
    )
    log_to_file(data_dir, entry)

    content = (data_dir / "audit.log").read_text(encoding="utf-8")
    assert "✗" in content
    assert "ERROR: email_failed" in content


def test_audit_decorator_logs_function_call(tmp_db_path: Path):
    """The @audit decorator auto-logs decorated function calls."""
    init_audit(tmp_db_path)

    from paperbot.audit import audit

    @audit(tmp_db_path, action="test_action")
    def my_func():
        return 42

    result = my_func()
    assert result == 42

    logs = get_audit_logs(tmp_db_path, action="test_action", limit=10)
    assert len(logs) == 1
    assert logs[0]["status"] == "success"
    assert logs[0]["details"]["result"] == 42
    assert logs[0]["duration_ms"] >= 0


def test_audit_decorator_captures_error(tmp_db_path: Path):
    """The @audit decorator logs exceptions and re-raises."""
    init_audit(tmp_db_path)

    from paperbot.audit import audit

    @audit(tmp_db_path, action="failing_action")
    def my_bad_func():
        raise ValueError("boom")

    try:
        my_bad_func()
    except ValueError:
        pass

    logs = get_audit_logs(tmp_db_path, action="failing_action", limit=10)
    assert len(logs) == 1
    assert logs[0]["status"] == "error"
    assert "boom" in logs[0]["error_message"]

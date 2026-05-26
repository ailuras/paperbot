"""Smoke tests for CLI commands."""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest
from typer.testing import CliRunner

from paperbot.cli import app
from paperbot.db import init_db, upsert_papers

runner = CliRunner()


def _strip_ansi(s: str) -> str:
    return re.sub(r"\x1b\[[0-9;]*m", "", s)


@pytest.fixture
def cli_env(tmp_path: Path, sample_config_dict: dict):
    """Prepare environment variables for CLI tests."""
    data_dir = tmp_path / "paperbot_data"
    data_dir.mkdir()
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(sample_config_dict), encoding="utf-8")
    return {
        "PAPERBOT_CONFIG": str(config_path),
        "PAPERBOT_DATA_DIR": str(data_dir),
    }


def test_cli_help():
    """CLI help lists all commands."""
    result = runner.invoke(app, ["--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "fetch" in out
    assert "recommend" in out
    assert "mark" in out
    assert "stats" in out
    assert "history" in out
    assert "serve" in out
    assert "init" in out


def test_fetch_help():
    """fetch command has expected options."""
    result = runner.invoke(app, ["fetch", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "--days" in out
    assert "--dry-run" in out


def test_recommend_help():
    """recommend command has expected options."""
    result = runner.invoke(app, ["recommend", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "--count" in out
    assert "--dry-run" in out


def test_init_help():
    """init command has expected options."""
    result = runner.invoke(app, ["init", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "--days" in out
    assert "365" in out


def test_mark_help():
    """mark command requires status option."""
    result = runner.invoke(app, ["mark", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "--status" in out


def test_stats_help():
    """stats command has no required args."""
    result = runner.invoke(app, ["stats", "--help"])
    assert result.exit_code == 0


def test_history_help():
    """history command has limit option."""
    result = runner.invoke(app, ["history", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "--limit" in out


def test_serve_help():
    """serve command has host/port/daemon options."""
    result = runner.invoke(app, ["serve", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "--host" in out
    assert "--port" in out
    assert "--daemon" in out


def test_stats_command(cli_env: dict):
    """stats command prints paper statistics."""
    result = runner.invoke(app, ["stats"], env=cli_env)
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "Total Papers" in out
    assert "States:" in out


def test_mark_command(cli_env: dict, sample_paper: dict):
    """mark command sets paper status."""
    db_path = Path(cli_env["PAPERBOT_DATA_DIR"]) / "paperbot.db"
    init_db(db_path)
    upsert_papers(db_path, [sample_paper])

    result = runner.invoke(
        app, ["mark", sample_paper["id"], "--status", "read"], env=cli_env
    )
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "read" in out


def test_audit_command(cli_env: dict):
    """audit command shows recent operations."""
    result = runner.invoke(app, ["audit"], env=cli_env)
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "No audit entries found" in out

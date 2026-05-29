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
    assert "update" in out


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
    assert "Recommended" in out


def test_mark_command(cli_env: dict, sample_paper: dict):
    """mark command sets paper status."""
    db_path = Path(cli_env["PAPERBOT_DATA_DIR"]) / "paperbot.db"
    init_db(db_path)
    upsert_papers(db_path, [sample_paper])

    result = runner.invoke(
        app, ["mark", sample_paper.id, "--status", "read"], env=cli_env
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


def test_recommend_dry_run(cli_env: dict, sample_papers, monkeypatch):
    """recommend --dry-run prints candidates without saving."""
    db_path = Path(cli_env["PAPERBOT_DATA_DIR"]) / "paperbot.db"
    init_db(db_path)
    upsert_papers(db_path, sample_papers)

    from paperbot import cli

    monkeypatch.setattr(cli, "get_unread_papers", lambda _db: sample_papers)

    def _fake_recommend(papers, cfg, count=None):
        from paperbot.recommend import RecommendationResult

        return [RecommendationResult(papers[0], "Quality Pick", 0)]

    monkeypatch.setattr(cli, "recommend_papers", _fake_recommend)

    result = runner.invoke(app, ["recommend", "--dry-run"], env=cli_env)
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "Dry run" in out
    assert sample_papers[0].title in out


def test_recommend_marks_recommended(cli_env: dict, sample_papers, monkeypatch):
    """recommend persists selected papers as recommended, not read."""
    db_path = Path(cli_env["PAPERBOT_DATA_DIR"]) / "paperbot.db"
    init_db(db_path)
    upsert_papers(db_path, sample_papers)

    from paperbot import cli
    from paperbot.db import get_stats

    def _fake_recommend(papers, cfg, count=None):
        from paperbot.recommend import RecommendationResult

        return [RecommendationResult(papers[0], "Quality Pick", 0)]

    monkeypatch.setattr(cli, "recommend_papers", _fake_recommend)

    result = runner.invoke(app, ["recommend", "--count", "1"], env=cli_env)
    assert result.exit_code == 0
    stats = get_stats(db_path)
    assert stats["recommended"] == 1
    assert stats["read"] == 0


def test_fetch_dry_run(cli_env: dict, monkeypatch):
    """fetch --dry-run prints report without saving."""
    from paperbot import cli

    def _fake_fetch(cfg, days=None):
        return [], {
            "range": "2024-01-01 ~ 2024-01-15",
            "days": 15,
            "track_stats": [{"track": "SMT", "raw": 5, "filtered": 3}],
            "total_raw": 5,
            "total_filtered": 3,
        }

    monkeypatch.setattr(cli, "fetch_papers", _fake_fetch)

    result = runner.invoke(app, ["fetch", "--dry-run"], env=cli_env)
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "Dry run" in out
    assert "SMT" in out


def test_update_recomputes_existing_papers_without_resetting_status(cli_env: dict):
    """update refreshes derived local fields while preserving paper state."""
    from paperbot.db import get_paper_by_id_or_title, get_stats, set_paper_status
    from paperbot.models import Paper

    db_path = Path(cli_env["PAPERBOT_DATA_DIR"]) / "paperbot.db"
    init_db(db_path)
    paper = Paper(
        id="W-update-1",
        title="Update Me",
        venue="CAV 2024 Computer Aided Verification",
        cited_by_count=0,
        score=0.0,
        tier=0,
        venue_abbr="Others",
    )
    upsert_papers(db_path, [paper])
    set_paper_status(db_path, paper.id, "read")

    result = runner.invoke(app, ["update"], env=cli_env)

    assert result.exit_code == 0
    updated = get_paper_by_id_or_title(db_path, paper.id)[0]
    assert updated.tier == 1
    assert updated.score == 5.0
    assert updated.venue_abbr == "CAV"
    stats = get_stats(db_path)
    assert stats["read"] == 1
    assert stats["pending"] == 0


def test_update_reset_marks_all_papers_pending(cli_env: dict, sample_paper):
    """update --reset clears paper state after refreshing local fields."""
    from paperbot.db import get_stats, set_paper_status

    db_path = Path(cli_env["PAPERBOT_DATA_DIR"]) / "paperbot.db"
    init_db(db_path)
    upsert_papers(db_path, [sample_paper])
    set_paper_status(db_path, sample_paper.id, "read")

    result = runner.invoke(app, ["update", "--reset"], env=cli_env)

    assert result.exit_code == 0
    stats = get_stats(db_path)
    assert stats["pending"] == 1
    assert stats["read"] == 0


def test_update_all_fetches_before_local_refresh(cli_env: dict, monkeypatch):
    """update --all refetches source data before recomputing local fields."""
    from paperbot import cli
    from paperbot.db import get_paper_by_id_or_title
    from paperbot.models import Paper

    fetched = Paper(
        id="W-update-all",
        title="Fetched Paper",
        venue="CAV 2024 Computer Aided Verification",
        cited_by_count=0,
        score=0.0,
        tier=0,
        venue_abbr="Others",
    )

    def _fake_fetch(cfg, days=None):
        return [fetched], {
            "range": "2024-01-01 ~ 2024-01-15",
            "days": days or 15,
            "track_stats": [{"track": "SMT", "raw": 1, "filtered": 1}],
            "total_raw": 1,
            "total_filtered": 1,
        }

    monkeypatch.setattr(cli, "fetch_papers", _fake_fetch)

    result = runner.invoke(app, ["update", "--all", "--days", "15"], env=cli_env)

    assert result.exit_code == 0
    db_path = Path(cli_env["PAPERBOT_DATA_DIR"]) / "paperbot.db"
    paper = get_paper_by_id_or_title(db_path, fetched.id)[0]
    assert paper.title == "Fetched Paper"
    assert paper.tier == 1
    assert paper.venue_abbr == "CAV"


def test_history_command(cli_env: dict, sample_papers):
    """history command lists recently read papers."""
    db_path = Path(cli_env["PAPERBOT_DATA_DIR"]) / "paperbot.db"
    init_db(db_path)
    upsert_papers(db_path, sample_papers)

    from paperbot.db import set_paper_status

    set_paper_status(db_path, sample_papers[0].id, "read")

    result = runner.invoke(app, ["history"], env=cli_env)
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "Recent Reads" in out
    assert "Read:" in out
    assert sample_papers[0].title in out


def test_history_empty(cli_env: dict):
    """history command handles empty state."""
    result = runner.invoke(app, ["history"], env=cli_env)
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "No recent reads" in out


def test_history_recommended_status(cli_env: dict, sample_papers):
    """history --status recommended lists recommendations separately from reads."""
    db_path = Path(cli_env["PAPERBOT_DATA_DIR"]) / "paperbot.db"
    init_db(db_path)
    upsert_papers(db_path, sample_papers)

    from paperbot.db import set_paper_status

    set_paper_status(db_path, sample_papers[0].id, "recommended")
    set_paper_status(db_path, sample_papers[1].id, "read")

    result = runner.invoke(
        app, ["history", "--status", "recommended"], env=cli_env
    )
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "Recent Recommendations" in out
    assert "Recommended:" in out
    assert sample_papers[0].title in out
    assert sample_papers[1].title not in out


def test_history_invalid_status(cli_env: dict):
    """history rejects unknown statuses instead of returning arbitrary state rows."""
    result = runner.invoke(app, ["history", "--status", "unknown"], env=cli_env)
    assert result.exit_code == 1
    out = _strip_ansi(result.output)
    assert "Invalid status" in out


def test_history_with_status(cli_env: dict, sample_papers):
    """history --status filters by paper state."""
    db_path = Path(cli_env["PAPERBOT_DATA_DIR"]) / "paperbot.db"
    init_db(db_path)
    upsert_papers(db_path, sample_papers)

    from paperbot.db import set_paper_status

    set_paper_status(db_path, sample_papers[0].id, "starred")

    result = runner.invoke(
        app, ["history", "--status", "starred"], env=cli_env
    )
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "Recent Starred Papers" in out
    assert sample_papers[0].title in out


def test_history_status_empty(cli_env: dict):
    """history --status handles empty state gracefully."""
    result = runner.invoke(app, ["history", "--status", "skip"], env=cli_env)
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "No recent skipped papers" in out


def test_serve_stop_not_running(cli_env: dict):
    """serve --stop reports not running when no server is active."""
    result = runner.invoke(app, ["serve", "--stop"], env=cli_env)
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "not running" in out.lower()


def test_serve_stop_running_exits_without_starting(cli_env: dict):
    """serve --stop exits after stopping and does not start the dashboard."""
    from unittest.mock import patch

    with patch("paperbot.cli.stop_server", return_value=True):
        with patch("paperbot.cli.run_dashboard") as mock_run:
            result = runner.invoke(
                app, ["serve", "--stop", "--port", "9999"], env=cli_env
            )

    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "Dashboard stopped" in out
    mock_run.assert_not_called()


def test_serve_restart_not_running(cli_env: dict):
    """serve --restart starts server when none is running."""
    from unittest.mock import patch

    with patch("paperbot.cli.stop_server", return_value=False):
        with patch("paperbot.cli.run_dashboard") as mock_run:
            result = runner.invoke(
                app, ["serve", "--restart", "--port", "9999"], env=cli_env
            )

    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "Restarting" in out
    mock_run.assert_called_once()

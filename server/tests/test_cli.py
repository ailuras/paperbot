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
    assert "recommend" in out
    assert "update" in out
    assert "papers" in out
    assert "dashboard" in out
    assert "logs" in out
    for legacy_command in ["fetch", "init", "mark", "stats", "history", "serve", "status", "audit"]:
        assert re.search(rf"\b{legacy_command}\b", out) is None


@pytest.mark.parametrize(
    "command",
    ["fetch", "init", "mark", "stats", "history", "serve", "status", "audit"],
)
def test_legacy_top_level_commands_removed(command: str):
    """Old top-level commands are not kept as compatibility aliases."""
    result = runner.invoke(app, [command, "--help"])
    assert result.exit_code != 0


def test_recommend_help():
    """recommend command has expected options."""
    result = runner.invoke(app, ["recommend", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "--count" in out
    assert "--dry-run" in out


def test_update_help():
    """update command exposes the new source/status options."""
    result = runner.invoke(app, ["update", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "--reset-db" in out
    assert "--days" in out
    assert "--reset-status" in out
    assert "--dry-run" in out
    assert "--email" not in out
    assert "--all" not in out


@pytest.mark.parametrize("old_option", ["--all", "--reset"])
def test_update_legacy_options_removed(old_option: str):
    """Old update flags are not kept."""
    result = runner.invoke(app, ["update", old_option])
    assert result.exit_code != 0


def test_papers_help():
    """papers groups paper-state operations."""
    result = runner.invoke(app, ["papers", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "mark" in out
    assert "history" not in out
    assert "stats" in out


def test_papers_mark_help():
    """papers mark requires status option."""
    result = runner.invoke(app, ["papers", "mark", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "--status" in out


def test_papers_stats_help():
    """papers stats has a status option."""
    result = runner.invoke(app, ["papers", "stats", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "--status" in out


def test_dashboard_help():
    """dashboard groups local service operations."""
    result = runner.invoke(app, ["dashboard", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "start" in out
    assert "stop" in out
    assert "restart" in out
    assert "status" in out


def test_dashboard_start_help():
    """dashboard start has host/port/daemon options."""
    result = runner.invoke(app, ["dashboard", "start", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "--host" in out
    assert "--port" in out
    assert "--daemon" in out
    assert "--log-file" in out


def test_dashboard_stop_help():
    """dashboard stop accepts a port."""
    result = runner.invoke(app, ["dashboard", "stop", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "--port" in out


def test_dashboard_restart_help():
    """dashboard restart has host/port/daemon options."""
    result = runner.invoke(app, ["dashboard", "restart", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "--host" in out
    assert "--port" in out
    assert "--daemon" in out


def test_dashboard_status_help():
    """dashboard status is available as a subcommand."""
    result = runner.invoke(app, ["dashboard", "status", "--help"])
    assert result.exit_code == 0


def test_logs_help():
    """logs lists audit entries by default."""
    result = runner.invoke(app, ["logs", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "--action" in out
    assert "--limit" in out
    assert "stats" in out


def test_logs_stats_help():
    """logs stats has a days option."""
    result = runner.invoke(app, ["logs", "stats", "--help"])
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "--days" in out


def test_stats_command(cli_env: dict):
    """stats command prints paper statistics."""
    result = runner.invoke(app, ["papers", "stats"], env=cli_env)
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
        app, ["papers", "mark", sample_paper.id, "--status", "read"], env=cli_env
    )
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "read" in out


def test_audit_command(cli_env: dict):
    """logs command shows recent operations."""
    result = runner.invoke(app, ["logs"], env=cli_env)
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


def test_update_fetch_dry_run(cli_env: dict, monkeypatch):
    """update --dry-run prints report without saving."""
    from paperbot import cli
    from paperbot.db import get_paper_by_id_or_title
    from paperbot.models import Paper

    fetched = Paper(
        id="W-update-dry-run",
        title="Fetched Dry Run Paper",
        venue="CAV 2024 Computer Aided Verification",
    )

    def _fake_fetch(cfg, days=None):
        return [fetched], {
            "range": "2024-01-01 ~ 2024-01-15",
            "days": 15,
            "track_stats": [{"track": "SMT", "raw": 5, "filtered": 3}],
            "total_raw": 5,
            "total_filtered": 3,
        }

    monkeypatch.setattr(cli, "fetch_papers", _fake_fetch)

    result = runner.invoke(app, ["update", "--dry-run"], env=cli_env)
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "Dry run" in out
    assert "SMT" in out
    db_path = Path(cli_env["PAPERBOT_DATA_DIR"]) / "paperbot.db"
    assert get_paper_by_id_or_title(db_path, fetched.id) == []


def test_update_recomputes_existing_papers_without_resetting_status(cli_env: dict, monkeypatch):
    """update refreshes derived local fields while preserving paper state."""
    from paperbot import cli
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

    def _fake_fetch(cfg, days=None):
        return [], {
            "range": "2024-01-01 ~ 2024-01-15",
            "days": days or 45,
            "track_stats": [],
            "total_raw": 0,
            "total_filtered": 0,
        }
    monkeypatch.setattr(cli, "fetch_papers", _fake_fetch)

    result = runner.invoke(app, ["update"], env=cli_env)

    assert result.exit_code == 0
    updated = get_paper_by_id_or_title(db_path, paper.id)[0]
    assert updated.tier == 1
    assert updated.score == 5.0
    assert updated.venue_abbr == "CAV"
    stats = get_stats(db_path)
    assert stats["read"] == 1
    assert stats["pending"] == 0


def test_update_reset_marks_all_papers_pending(cli_env: dict, sample_paper, monkeypatch):
    """update --reset-status clears paper state after refreshing local fields."""
    from paperbot import cli
    from paperbot.db import get_stats, set_paper_status

    db_path = Path(cli_env["PAPERBOT_DATA_DIR"]) / "paperbot.db"
    init_db(db_path)
    upsert_papers(db_path, [sample_paper])
    set_paper_status(db_path, sample_paper.id, "read")

    def _fake_fetch(cfg, days=None):
        return [], {
            "range": "2024-01-01 ~ 2024-01-15",
            "days": days or 45,
            "track_stats": [],
            "total_raw": 0,
            "total_filtered": 0,
        }
    monkeypatch.setattr(cli, "fetch_papers", _fake_fetch)

    result = runner.invoke(app, ["update", "--reset-status"], env=cli_env)

    assert result.exit_code == 0
    stats = get_stats(db_path)
    assert stats["pending"] == 1
    assert stats["read"] == 0


def test_update_fetches_before_local_refresh(cli_env: dict, monkeypatch):
    """update refetches source data before recomputing local fields."""
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

    result = runner.invoke(app, ["update", "--days", "15"], env=cli_env)

    assert result.exit_code == 0
    db_path = Path(cli_env["PAPERBOT_DATA_DIR"]) / "paperbot.db"
    paper = get_paper_by_id_or_title(db_path, fetched.id)[0]
    assert paper.title == "Fetched Paper"
    assert paper.tier == 1
    assert paper.venue_abbr == "CAV"


def test_update_reset_db(cli_env: dict, monkeypatch):
    """update --reset-db recomputes derived fields without fetching."""
    from paperbot import cli
    from paperbot.db import get_paper_by_id_or_title
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

    def _fail_fetch(cfg, days=None):
        pytest.fail("fetch_papers should not be called when --reset-db is set")

    monkeypatch.setattr(cli, "fetch_papers", _fail_fetch)

    result = runner.invoke(app, ["update", "--reset-db"], env=cli_env)
    assert result.exit_code == 0

    updated = get_paper_by_id_or_title(db_path, paper.id)[0]
    assert updated.tier == 1
    assert updated.score == 5.0
    assert updated.venue_abbr == "CAV"


def test_stats_with_status(cli_env: dict, sample_papers):
    """stats --status lists papers with specified status."""
    db_path = Path(cli_env["PAPERBOT_DATA_DIR"]) / "paperbot.db"
    init_db(db_path)
    upsert_papers(db_path, sample_papers)

    from paperbot.db import set_paper_status

    set_paper_status(db_path, sample_papers[0].id, "read")

    result = runner.invoke(app, ["papers", "stats", "--status", "read"], env=cli_env)
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "PaperBot Stats" in out
    assert "Recent Reads" in out
    assert sample_papers[0].title in out


def test_stats_status_empty(cli_env: dict):
    """stats --status handles empty state gracefully."""
    result = runner.invoke(app, ["papers", "stats", "--status", "skip"], env=cli_env)
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "No recent skipped papers" in out


def test_stats_invalid_status(cli_env: dict):
    """stats --status rejects unknown statuses."""
    result = runner.invoke(app, ["papers", "stats", "--status", "unknown"], env=cli_env)
    assert result.exit_code == 1
    out = _strip_ansi(result.output)
    assert "Invalid status" in out


def test_dashboard_stop_not_running(cli_env: dict):
    """dashboard stop reports not running when no server is active."""
    result = runner.invoke(app, ["dashboard", "stop"], env=cli_env)
    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "not running" in out.lower()


def test_dashboard_stop_running_exits_without_starting(cli_env: dict):
    """dashboard stop exits after stopping and does not start the dashboard."""
    from unittest.mock import patch

    with patch("paperbot.cli.stop_server", return_value=True):
        with patch("paperbot.cli.run_dashboard") as mock_run:
            result = runner.invoke(
                app, ["dashboard", "stop", "--port", "9999"], env=cli_env
            )

    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "Dashboard stopped" in out
    mock_run.assert_not_called()


def test_dashboard_restart_not_running(cli_env: dict):
    """dashboard restart starts server when none is running."""
    from unittest.mock import patch

    with patch("paperbot.cli.stop_server", return_value=False):
        with patch("paperbot.cli.run_dashboard") as mock_run:
            result = runner.invoke(
                app, ["dashboard", "restart", "--port", "9999"], env=cli_env
            )

    assert result.exit_code == 0
    out = _strip_ansi(result.output)
    assert "Restarting" in out
    mock_run.assert_called_once()

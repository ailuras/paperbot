"""Tests for config loading and validation."""

from __future__ import annotations

from pathlib import Path

from paperbot.config import default_config_path, load_config, load_default_config


def test_load_config_from_file(tmp_config_file: Path):
    """Config loads correctly from a JSON file."""
    cfg = load_config(tmp_config_file)
    assert "SMT" in cfg.tracks
    assert cfg.tracks["SMT"].query == "smt solver"
    assert cfg.scoring.tiers["1"].points == 5


def test_load_config_creates_default_data_dir(tmp_config_file: Path, tmp_path: Path):
    """Loading config creates the data directory."""
    cfg = load_config(tmp_config_file)
    assert cfg.data_dir.exists()


def test_default_config_path_exists():
    """The default config path points to data/config.json."""
    path = default_config_path()
    assert path.name == "config.json"
    assert "data" in str(path)


def test_env_override_data_dir(tmp_config_file: Path, tmp_path: Path, monkeypatch):
    """PAPERBOT_DATA_DIR env var overrides data_dir."""
    custom_dir = tmp_path / "custom_paperbot"
    monkeypatch.setenv("PAPERBOT_DATA_DIR", str(custom_dir))
    cfg = load_config(tmp_config_file)
    assert cfg.data_dir == custom_dir


def test_load_default_config_uses_env_config(tmp_config_file: Path, tmp_path: Path, monkeypatch):
    """load_default_config honors PAPERBOT_CONFIG."""
    monkeypatch.setenv("PAPERBOT_CONFIG", str(tmp_config_file))
    monkeypatch.setenv("PAPERBOT_DATA_DIR", str(tmp_path / "data"))
    cfg = load_default_config()
    assert cfg.tracks["SMT"].query == "smt solver"


def test_openalex_defaults():
    """OpenAlex config has sensible defaults."""
    from paperbot.config import OpenAlexConfig

    oa = OpenAlexConfig()
    assert oa.base_url == "https://api.openalex.org/works"
    assert oa.timeout_seconds == 20
    assert oa.per_page == 100
    assert oa.default_days == 45


def test_mail_config_defaults():
    """Mail config has sensible defaults."""
    from paperbot.config import MailConfig

    mail = MailConfig()
    assert mail.smtp_port == 587
    assert mail.use_tls is True
    assert mail.from_name == "PaperBot"
    assert mail.dashboard_url == "http://localhost:8765"


def test_recommendation_defaults():
    """Recommendation config has sensible defaults."""
    from paperbot.config import RecommendationConfig

    rec = RecommendationConfig()
    assert rec.daily_count == 3
    assert rec.quality_slots == 1
    assert rec.high_score_threshold == 5
    assert rec.recent_days == 30

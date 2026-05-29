"""Configuration model and loader."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field


class TrackConfig(BaseModel):
    query: str
    keywords: list[str]
    color: str = ""  # optional CSS color override for track badges


class OpenAlexConfig(BaseModel):
    base_url: str = "https://api.openalex.org/works"
    mailto: str = ""
    api_key_env: str = "OPENALEX_API_KEY"
    timeout_seconds: int = 20
    per_page: int = 100
    default_days: int = 45
    default_max_results: int = 1000
    topic_filter: str = "topics.field.id:17"


class FiltersConfig(BaseModel):
    title_blacklist: list[str] = Field(default_factory=list)
    source_blacklist: list[str] = Field(default_factory=list)
    venue_blacklist: list[str] = Field(default_factory=list)


class ScoringTier(BaseModel):
    points: int
    venues: dict[str, list[str]] = Field(default_factory=dict)


class CitationBreakpoint(BaseModel):
    up_to: int | None
    points_per_citation: float


class ScoringConfig(BaseModel):
    tiers: dict[str, ScoringTier]
    citation_breakpoints: list[CitationBreakpoint]
    max_citation_points: int = 40


class RecommendationConfig(BaseModel):
    daily_count: int = 3
    quality_slots: int = 1
    high_score_threshold: int = 5
    recent_days: int = 30


class TranslateConfig(BaseModel):
    enabled: bool = False
    target_language: str = "中文"
    model: str = "deepseek-v4-flash"
    include_in_email: bool = True


class MailConfig(BaseModel):
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    from_addr: str = ""
    from_name: str = "PaperBot"
    to_addrs: list[str] = Field(default_factory=list)
    use_tls: bool = True
    dashboard_url: str = "http://localhost:8765"


class Settings(BaseModel):
    data_dir: Path = Field(default_factory=lambda: Path.home() / ".paperbot")
    openalex: OpenAlexConfig = Field(default_factory=OpenAlexConfig)
    tracks: dict[str, TrackConfig]
    filters: FiltersConfig = Field(default_factory=FiltersConfig)
    scoring: ScoringConfig
    recommendation: RecommendationConfig = Field(default_factory=RecommendationConfig)
    translate: TranslateConfig = Field(default_factory=TranslateConfig)
    mail: MailConfig = Field(default_factory=MailConfig)

    model_config = {"populate_by_name": True}


def default_config_path() -> Path:
    return Path(__file__).resolve().parents[2] / "data" / "config.json"


def load_default_config() -> Settings:
    """Load config from the default path (env var or package data dir)."""
    return load_config()


def load_config(path: Path | str | None = None) -> Settings:
    if path is None:
        env = os.getenv("PAPERBOT_CONFIG")
        path = Path(env) if env else default_config_path()
    else:
        path = Path(path)

    path = path.expanduser()
    if not path.exists():
        # Try to copy from example template
        example = path.with_suffix(path.suffix + ".example")
        if example.exists():
            import shutil

            shutil.copy(example, path)
        else:
            raise FileNotFoundError(f"Config file not found: {path}")

    with path.open() as f:
        raw: dict[str, Any] = json.load(f)

    data_dir = Path(raw.get("data_dir", "~/.paperbot")).expanduser()

    # Allow overriding data_dir via environment variable
    env_data_dir = os.getenv("PAPERBOT_DATA_DIR")
    if env_data_dir:
        data_dir = Path(env_data_dir).expanduser()

    data_dir.mkdir(parents=True, exist_ok=True)

    return Settings(data_dir=data_dir, **{k: v for k, v in raw.items() if k != "data_dir"})

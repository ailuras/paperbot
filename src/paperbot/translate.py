"""Paper translation via DeepSeek API."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx

from paperbot.config import Settings
from paperbot.models import Paper

# Lower temperature for stable, deterministic translations
_TEMPERATURE = 0.3
# Enough for long abstracts (typical academic abstract ~200-500 tokens)
_MAX_TOKENS = 4096
# Network timeout for API calls
_REQUEST_TIMEOUT = 60


@dataclass(frozen=True)
class TranslationResult:
    title_zh: str
    abstract_zh: str
    source: str  # "api" or "cache"


def _call_deepseek(text: str, system_prompt: str, settings: Settings | None = None) -> str:
    """Call DeepSeek API for translation."""
    if settings is None:
        try:
            from paperbot.config import load_default_config
            settings = load_default_config()
        except Exception:
            pass

    api_key_env = settings.translate.api_key_env if settings else "DEEPSEEK_API_KEY"
    api_key = os.environ.get(api_key_env, "")
    if not api_key:
        raise RuntimeError(f"{api_key_env} environment variable not set")

    base_url = settings.translate.base_url if settings else "https://api.deepseek.com"
    model = settings.translate.model if settings else "deepseek-v4-flash"

    url = f"{base_url.rstrip('/')}/chat/completions"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload: dict[str, Any] = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": text},
        ],
        "temperature": _TEMPERATURE,
        "max_tokens": _MAX_TOKENS,
    }

    resp = httpx.post(url, headers=headers, json=payload, timeout=_REQUEST_TIMEOUT)
    resp.raise_for_status()
    data = resp.json()
    return data["choices"][0]["message"]["content"].strip()


def translate_paper(
    title: str,
    abstract: str | None = None,
    settings: Settings | None = None,
) -> TranslationResult:
    """Translate paper title and abstract via DeepSeek API.

    Args:
        title: Paper title in English.
        abstract: Paper abstract in English (optional).
        settings: Settings configuration containing translation settings.

    Returns:
        TranslationResult with Chinese translations.
    """
    target_lang = settings.translate.target_language if settings else "中文"

    title_prompt = (
        "You are a professional academic translator. "
        f"Translate the following paper title into {target_lang}. "
        "Preserve technical terms in English where appropriate. "
        "Return ONLY the translated title, no explanations."
    )
    abstract_prompt = (
        "You are a professional academic translator. "
        f"Translate the following paper abstract into {target_lang}. "
        "Preserve technical terms in English where appropriate. "
        "Return ONLY the translated text, no explanations."
    )

    title_zh = _call_deepseek(title, title_prompt, settings)
    abstract_zh = ""
    if abstract and abstract.strip():
        abstract_zh = _call_deepseek(abstract, abstract_prompt, settings)

    return TranslationResult(
        title_zh=title_zh,
        abstract_zh=abstract_zh,
        source="api",
    )


def translate_paper_cached(
    db_path: Path,
    paper: Paper,
    settings: Settings | None = None,
) -> dict[str, str]:
    """Translate a paper with DB caching.

    Checks the translation cache first; on miss, calls the API and stores
    the result.  Returns a dict with title_zh, abstract_zh, and source.
    """
    from paperbot.db import get_paper_translation, set_paper_translation

    cached = get_paper_translation(db_path, paper.id)
    if cached.get("title_zh"):
        return {**cached, "source": "cache"}

    result = translate_paper(title=paper.title, abstract=paper.abstract, settings=settings)
    set_paper_translation(db_path, paper.id, result.title_zh, result.abstract_zh)
    return {
        "title_zh": result.title_zh,
        "abstract_zh": result.abstract_zh,
        "source": "api",
    }


def translate_text(text: str, target_language: str = "中文") -> str:
    """Translate arbitrary text via DeepSeek API.

    Args:
      text: Text to translate.
      target_language: Target language, defaults to Chinese.

    Returns:
      Translated text.
    """
    system = (
        f"You are a professional translator. "
        f"Translate the user's text into {target_language}. "
        f"Preserve technical terms in the original language where appropriate. "
        f"Return ONLY the translated text, no explanations."
    )
    return _call_deepseek(text, system)

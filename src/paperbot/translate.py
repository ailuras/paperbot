"""Paper translation via DeepSeek API."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from paperbot.models import Paper

import requests

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY", "")
DEEPSEEK_BASE_URL = "https://api.deepseek.com"
DEEPSEEK_MODEL = "deepseek-v4-flash"

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


def _call_deepseek(text: str, system_prompt: str) -> str:
    """Call DeepSeek API for translation."""
    if not DEEPSEEK_API_KEY:
        raise RuntimeError("DEEPSEEK_API_KEY environment variable not set")

    url = f"{DEEPSEEK_BASE_URL}/chat/completions"
    headers = {
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}",
        "Content-Type": "application/json",
    }
    payload: dict[str, Any] = {
        "model": DEEPSEEK_MODEL,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": text},
        ],
        "temperature": _TEMPERATURE,
        "max_tokens": _MAX_TOKENS,
    }

    resp = requests.post(url, headers=headers, json=payload, timeout=_REQUEST_TIMEOUT)
    resp.raise_for_status()
    data = resp.json()
    return data["choices"][0]["message"]["content"].strip()


_TRANSLATE_TITLE_PROMPT = (
    "You are a professional academic translator. "
    "Translate the following paper title into Chinese. "
    "Preserve technical terms in English where appropriate. "
    "Return ONLY the translated title, no explanations."
)

_TRANSLATE_ABSTRACT_PROMPT = (
    "You are a professional academic translator. "
    "Translate the following paper abstract into Chinese. "
    "Preserve technical terms in English where appropriate. "
    "Return ONLY the translated text, no explanations."
)


def translate_paper(title: str, abstract: str | None = None) -> TranslationResult:
    """Translate paper title and abstract via DeepSeek API.

    Args:
        title: Paper title in English.
        abstract: Paper abstract in English (optional).

    Returns:
        TranslationResult with Chinese translations.
    """
    title_zh = _call_deepseek(title, _TRANSLATE_TITLE_PROMPT)
    abstract_zh = ""
    if abstract and abstract.strip():
        abstract_zh = _call_deepseek(abstract, _TRANSLATE_ABSTRACT_PROMPT)

    return TranslationResult(
        title_zh=title_zh,
        abstract_zh=abstract_zh,
        source="api",
    )


def translate_paper_cached(db_path: Path, paper: Paper) -> dict[str, str]:
    """Translate a paper with DB caching.

    Checks the translation cache first; on miss, calls the API and stores
    the result.  Returns a dict with title_zh, abstract_zh, and source.
    """
    from paperbot.db import get_paper_translation, set_paper_translation

    cached = get_paper_translation(db_path, paper.id)
    if cached.get("title_zh"):
        return {**cached, "source": "cache"}

    result = translate_paper(title=paper.title, abstract=paper.abstract)
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

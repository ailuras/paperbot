"""Shared utility helpers."""

from __future__ import annotations

import json
import re
from datetime import datetime
from typing import Any

DATE_FORMAT = "%Y-%m-%d"


def format_date(dt: datetime | None = None) -> str:
    """Return a consistently formatted date string."""
    if dt is None:
        dt = datetime.now()
    return dt.strftime(DATE_FORMAT)


def _abbr(venue: str) -> str:
    """Extract an acronym from a venue string, or return a short prefix."""
    if not venue:
        return "?"
    m = re.search(r"\b[A-Z]{2,}\b", venue)
    return m.group(0) if m else venue[:10]


def format_authors(paper: dict[str, Any]) -> str:
    """Normalize and format the authors field of a paper dict.

    Handles authors stored as a JSON string or a list, and truncates
    to the first three names followed by 'et al.' when applicable.
    """
    authors = paper.get("authors", [])
    if isinstance(authors, str):
        try:
            authors = json.loads(authors)
        except json.JSONDecodeError:
            authors = [authors]
    if not isinstance(authors, list):
        authors = [str(authors)] if authors else []

    author_str = ", ".join(authors[:3])
    if len(authors) > 3:
        author_str += ", et al."
    return author_str

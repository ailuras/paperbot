"""Shared utility helpers."""

from __future__ import annotations

import re
from datetime import datetime

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

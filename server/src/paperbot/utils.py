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


def compute_venue_abbr(venue: str) -> str:
    """Classify a venue into a display abbreviation.

    Rules:
      - arXiv  →  "arXiv"
      - Known conference / journal (matched by config scoring venues) → acronym
      - Everything else  →  "Others"
    """
    if not venue:
        return "Others"

    venue_lower = venue.lower()

    # arXiv papers
    if "arxiv" in venue_lower:
        return "arXiv"

    # Try to load config dynamically to avoid circular dependencies
    try:
        from paperbot.config import load_default_config
        settings = load_default_config()

        # Gather all (acronym, keyword) pairs to sort by keyword length descending,
        # ensuring that more specific/longer phrases are matched first.
        candidates = []
        for tier in settings.scoring.tiers.values():
            for abbr, keywords in tier.venues.items():
                for kw in keywords:
                    candidates.append((abbr, kw))

        candidates.sort(key=lambda x: len(x[1]), reverse=True)

        for abbr, kw in candidates:
            if kw.lower() in venue_lower:
                return abbr

        # If no phrase matched, fallback to checking the exact acronym as a word boundary
        for tier in settings.scoring.tiers.values():
            for abbr in tier.venues.keys():
                pattern = r"\b" + re.escape(abbr.lower()) + r"\b"
                if re.search(pattern, venue_lower):
                    return abbr
    except Exception:
        pass

    return "Others"

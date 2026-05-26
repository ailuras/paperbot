"""Domain models for PaperBot."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from typing import Any


class PaperStatus:
    """Valid paper statuses."""

    PENDING = "pending"
    READ = "read"
    STARRED = "starred"
    SKIP = "skip"

    ALL = {PENDING, READ, STARRED, SKIP}


@dataclass
class Paper:
    """A research paper with metadata and scoring information."""

    id: str = ""
    doi: str | None = None
    title: str = ""
    authors: list[str] = field(default_factory=list)
    publication_year: int | None = None
    publication_date: str = ""
    venue: str = ""
    cited_by_count: int = 0
    abstract: str = ""
    landing_page_url: str = ""
    pdf_url: str | None = None
    track: str = ""
    score: float = 0.0
    tier: int = 0
    created_at: str = ""
    updated_at: str = ""
    # Joined from paper_states
    status: str = "pending"
    changed_at: str = ""

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Paper":
        """Build a Paper from a raw dict (e.g. DB row or API response).

        Handles authors stored as a JSON string or a list.
        """
        authors = data.get("authors", [])
        if isinstance(authors, str):
            try:
                authors = json.loads(authors)
            except json.JSONDecodeError:
                authors = [authors] if authors else []
        if not isinstance(authors, list):
            authors = [str(authors)] if authors else []

        # tier may be stored as string in the DB
        tier_raw = data.get("tier", 0)
        try:
            tier = int(tier_raw) if tier_raw is not None else 0
        except (ValueError, TypeError):
            tier = 0

        return cls(
            id=data.get("id", ""),
            doi=data.get("doi"),
            title=data.get("title", ""),
            authors=authors,
            publication_year=data.get("publication_year"),
            publication_date=data.get("publication_date", ""),
            venue=data.get("venue", ""),
            cited_by_count=data.get("cited_by_count", 0) or 0,
            abstract=data.get("abstract", ""),
            landing_page_url=data.get("landing_page_url", ""),
            pdf_url=data.get("pdf_url"),
            track=data.get("track", ""),
            score=data.get("score", 0.0) or 0.0,
            tier=tier,
            created_at=data.get("created_at", ""),
            updated_at=data.get("updated_at", ""),
            status=data.get("status", "pending") or "pending",
            changed_at=data.get("changed_at", ""),
        )

    def to_dict(self) -> dict[str, Any]:
        """Serialize to a plain dict suitable for JSON or DB insertion.

        Authors are kept as a list; callers that need a JSON string must
        handle the conversion themselves.
        """
        return asdict(self)

    @property
    def author_str(self) -> str:
        """Short author list for display (first 3 + et al.)."""
        s = ", ".join(self.authors[:3])
        if len(self.authors) > 3:
            s += ", et al."
        return s

    @property
    def url(self) -> str:
        """Best available URL for the paper."""
        return self.landing_page_url or self.doi or self.id

    @property
    def year_or_date(self) -> str:
        """Publication year or date string for display."""
        return self.publication_date or str(self.publication_year) or "?"

"""Fetch papers from OpenAlex API."""

from __future__ import annotations

import os
import re
import time
from datetime import date, timedelta
from typing import Any

import httpx

from paperbot.config import ScoringTier, Settings, TrackConfig
from paperbot.models import Paper
from paperbot.utils import compute_venue_abbr

SELECT_FIELDS = ",".join(
    [
        "id",
        "doi",
        "display_name",
        "title",
        "authorships",
        "publication_year",
        "publication_date",
        "cited_by_count",
        "abstract_inverted_index",
        "primary_location",
        "open_access",
        "type",
        "relevance_score",
    ]
)


class VenueScorer:
    """Score papers by venue tier and citation count."""

    def __init__(self, settings: Settings):
        self.scoring = settings.scoring
        self.venue_blacklist = [v.lower() for v in settings.filters.venue_blacklist]

    def get_tier(self, venue: str) -> int:
        if not venue:
            return 0
        venue_lower = venue.lower()
        if any(token in venue_lower for token in self.venue_blacklist):
            return 0

        tiers = self.scoring.tiers
        sorted_tier_nums = sorted(int(k) for k in tiers)
        for tier_num in sorted_tier_nums:
            tier = tiers[str(tier_num)]
            acronyms = tier.acronyms
            if acronyms:
                pattern = r"\b(" + "|".join(re.escape(a.lower()) for a in acronyms) + r")\b"
                if re.search(pattern, venue_lower):
                    return tier_num
            for phrase in tier.phrases:
                phrase_lower = phrase.lower()
                if phrase_lower in venue_lower:
                    if self._has_more_specific_lower_tier_phrase(
                        venue_lower, phrase_lower, tier_num, sorted_tier_nums
                    ):
                        continue
                    return tier_num
        return 0

    def _has_more_specific_lower_tier_phrase(
        self,
        venue_lower: str,
        phrase_lower: str,
        tier: int,
        sorted_tiers: list[int],
    ) -> bool:
        for lower_tier in (t for t in sorted_tiers if t > tier):
            for lower_phrase in self.scoring.tiers[str(lower_tier)].phrases:
                lp = lower_phrase.lower()
                if phrase_lower in lp and lp in venue_lower and lp != phrase_lower:
                    return True
        return False

    def citation_score(self, citations: int) -> float:
        remaining = citations or 0
        previous_limit = 0
        score = 0.0
        for seg in self.scoring.citation_breakpoints:
            up_to = seg.up_to
            rate = seg.points_per_citation
            if up_to is None:
                count = max(0, remaining)
            else:
                count = max(0, min(remaining, up_to - previous_limit))
            score += count * rate
            remaining -= count
            if up_to is not None:
                previous_limit = up_to
            if remaining <= 0:
                break
        return min(score, self.scoring.max_citation_points)

    def calculate_score(self, venue: str, citations: int) -> float:
        tier = self.get_tier(venue)
        base = float(self.scoring.tiers.get(str(tier), ScoringTier(points=0)).points)
        return base + self.citation_score(citations)


def _restore_abstract(inverted_index: dict[str, list[int]] | None) -> str:
    if not inverted_index:
        return ""
    positions = [(idx, word) for word, indexes in inverted_index.items() for idx in indexes]
    return " ".join(word for _, word in sorted(positions))


def _parse_work(work: dict[str, Any], track: str, scorer: VenueScorer) -> Paper:
    loc = work.get("primary_location") or {}
    source = loc.get("source") or {}
    venue = source.get("display_name") or ""
    citations = work.get("cited_by_count", 0) or 0
    tier = scorer.get_tier(venue)
    venue_abbr = compute_venue_abbr(venue)

    return Paper(
        id=work.get("id") or "",
        doi=work.get("doi") or None,
        title=work.get("display_name") or work.get("title") or "",
        authors=[
            a.get("author", {}).get("display_name")
            for a in (work.get("authorships") or [])
            if a.get("author", {}).get("display_name")
        ],
        publication_year=work.get("publication_year"),
        publication_date=work.get("publication_date") or "",
        venue=venue,
        venue_abbr=venue_abbr,
        cited_by_count=citations,
        abstract=_restore_abstract(work.get("abstract_inverted_index")),
        landing_page_url=loc.get("landing_page_url")
        or work.get("doi")
        or work.get("id")
        or "",
        pdf_url=loc.get("pdf_url")
        or (work.get("open_access") or {}).get("oa_url")
        or None,
        track=track,
        score=scorer.calculate_score(venue, citations),
        tier=tier,
    )


def _is_relevant(paper: Paper, track: str, settings: Settings) -> bool:
    title_lower = paper.title.lower()
    text = f"{title_lower} {paper.abstract.lower()}"
    filters = settings.filters
    if any(token in title_lower for token in filters.title_blacklist):
        return False
    if any(token in paper.venue.lower() for token in filters.source_blacklist):
        return False
    keywords = settings.tracks.get(track, TrackConfig(query="", keywords=[])).keywords
    return any(
        re.search(
            rf"(?<![a-z0-9]){re.escape(keyword.lower())}(?![a-z0-9])",
            text,
        )
        for keyword in keywords
    )


def _search_papers(
    client: httpx.Client,
    query: str,
    from_date: str,
    to_date: str,
    max_results: int,
    settings: Settings,
) -> list[dict[str, Any]]:
    papers: list[dict[str, Any]] = []
    cursor = "*"
    base_url = settings.openalex.base_url
    per_page = settings.openalex.per_page
    topic_filter = settings.openalex.topic_filter
    mailto = os.environ.get("OPENALEX_MAILTO") or settings.openalex.mailto
    api_key = os.environ.get(settings.openalex.api_key_env, "")

    while len(papers) < max_results:
        filters = [
            f"from_publication_date:{from_date}",
            f"to_publication_date:{to_date}",
            "type:article",
        ]
        if topic_filter:
            filters.append(topic_filter)
        params: dict[str, Any] = {
            "search": query,
            "filter": ",".join(filters),
            "sort": "publication_date:desc,relevance_score:desc",
            "per_page": min(per_page, max_results - len(papers)),
            "cursor": cursor,
            "select": SELECT_FIELDS,
        }
        if mailto:
            params["mailto"] = mailto
        if api_key:
            params["api_key"] = api_key

        resp = client.get(base_url, params=params)
        resp.raise_for_status()
        data = resp.json()

        batch = data.get("results", [])
        papers.extend(batch)
        cursor = (data.get("meta") or {}).get("next_cursor")
        if not batch or not cursor:
            break
        time.sleep(0.1)

    return papers


def _dedupe_and_merge_tracks(papers: list[Paper]) -> list[Paper]:
    """Merge duplicate papers (same id) and combine tracks."""
    by_id: dict[str, Paper] = {}
    for paper in papers:
        pid = paper.id
        if not pid:
            continue
        if pid in by_id:
            existing = by_id[pid]
            tracks = {t.strip() for t in existing.track.split(",") if t.strip()}
            if paper.track:
                tracks.add(paper.track)
            # Update in place: combined track and higher score
            existing.track = ",".join(sorted(tracks))
            existing.score = max(existing.score, paper.score)
        else:
            by_id[pid] = paper
    return list(by_id.values())


def fetch_papers(
    settings: Settings,
    days: int | None = None,
    max_results: int | None = None,
) -> tuple[list[Paper], dict[str, Any]]:
    """Fetch papers from OpenAlex for all tracks.

    Returns (papers, stats).
    """
    openalex = settings.openalex
    days = days or openalex.default_days
    max_results = max_results or openalex.default_max_results

    today = date.today()
    from_day = today - timedelta(days=days - 1)

    scorer = VenueScorer(settings)
    track_stats: list[dict[str, Any]] = []
    all_papers: list[Paper] = []

    user_agent = "PaperBot/1.0"
    mailto = os.environ.get("OPENALEX_MAILTO") or openalex.mailto
    if mailto:
        user_agent += f" (mailto:{mailto})"

    with httpx.Client(
        headers={"User-Agent": user_agent},
        timeout=openalex.timeout_seconds,
    ) as client:
        for track, track_config in settings.tracks.items():
            works = _search_papers(
                client,
                track_config.query,
                from_day.isoformat(),
                today.isoformat(),
                max_results,
                settings,
            )
            papers = [_parse_work(w, track, scorer) for w in works]
            papers = [p for p in papers if _is_relevant(p, track, settings)]
            track_stats.append({
                "track": track,
                "raw": len(works),
                "filtered": len(papers),
            })
            all_papers.extend(papers)

    all_papers = _dedupe_and_merge_tracks(all_papers)

    stats = {
        "range": f"{from_day.isoformat()} ~ {today.isoformat()}",
        "days": days,
        "track_stats": track_stats,
        "total_raw": sum(s["raw"] for s in track_stats),
        "total_filtered": len(all_papers),
    }

    return all_papers, stats

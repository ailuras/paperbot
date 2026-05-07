#!/usr/bin/env python3
"""Fetch, filter, score, and merge papers from OpenAlex."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from datetime import date, timedelta
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_ROOT = SCRIPT_DIR.parent
# Try repo-relative data dir first (for git clones), fallback to workspace
_REPO_DATA = SKILL_ROOT.parent / "data"
_WORKSPACE_DATA = Path("~/.openclaw/workspace/paperdaily").expanduser()
DEFAULT_DATA_DIR = _REPO_DATA if _REPO_DATA.is_dir() else _WORKSPACE_DATA

def load_config(config_path: Optional[str] = None) -> Dict[str, Any]:
    path = Path(config_path).expanduser() if config_path else (DEFAULT_DATA_DIR / "config.json")
    with open(path) as f:
        config = json.load(f)
    data_file = Path(config["data_file"]).expanduser()
    if not data_file.is_absolute():
        data_file = (path.parent / data_file).resolve()
    config["_data_dir"] = str(path.parent)
    config["_data_file"] = str(data_file)
    return config


SELECT_FIELDS = ",".join([
    "id", "doi", "display_name", "title", "authorships", "publication_year",
    "publication_date", "cited_by_count", "abstract_inverted_index",
    "primary_location", "open_access", "type", "relevance_score",
])


class VenueScorer:
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.venue_blacklist = [v.lower() for v in config["filters"].get("venue_blacklist", [])]
        self.tiers = config["scoring"].get("tiers", {})

    def get_tier(self, venue: str) -> int:
        if not venue:
            return 0
        venue_lower = venue.lower()
        if any(token in venue_lower for token in self.venue_blacklist):
            return 0

        for tier in sorted((int(k) for k in self.tiers.keys())):
            tier_config = self.tiers[str(tier)]
            acronyms = tier_config.get("acronyms", [])
            if acronyms and re.search(r"\b(" + "|".join(re.escape(a) for a in acronyms) + r")\b", venue):
                return tier
            for phrase in tier_config.get("phrases", []):
                if phrase.lower() in venue_lower:
                    if phrase == "Artificial Intelligence" and "tools with" in venue_lower:
                        continue
                    return tier
        return 0

    def citation_score(self, citations: int) -> float:
        remaining = citations or 0
        previous_limit = 0
        score = 0.0
        for segment in self.config["scoring"].get("citation_breakpoints", []):
            up_to = segment.get("up_to")
            rate = float(segment.get("points_per_citation", 0))
            if up_to is None:
                count = max(0, remaining)
            else:
                count = max(0, min(remaining, int(up_to) - previous_limit))
            score += count * rate
            remaining -= count
            if up_to is not None:
                previous_limit = int(up_to)
            if remaining <= 0:
                break
        return min(score, float(self.config["scoring"].get("max_citation_points", 40)))

    def calculate_score(self, venue: str, citations: int) -> float:
        tier = self.get_tier(venue)
        base = float(self.tiers.get(str(tier), {}).get("points", 0))
        return base + self.citation_score(citations)


class PaperFetcher:
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        openalex = config["openalex"]
        self.base_url = openalex["base_url"]
        self.timeout = int(openalex["timeout_seconds"])
        self.per_page = int(openalex["per_page"])
        self.topic_filter = openalex.get("topic_filter", "")
        self.mailto = os.environ.get("OPENALEX_MAILTO") or openalex.get("mailto", "")
        self.api_key = os.environ.get(openalex.get("api_key_env", "OPENALEX_API_KEY"), "")
        user_agent = "PaperDaily/1.0"
        if self.mailto:
            user_agent += f" (mailto:{self.mailto})"
        self.headers = {"User-Agent": user_agent}
        self.scorer = VenueScorer(config)

    def api_get(self, url: str) -> Optional[Dict[str, Any]]:
        for attempt in range(2):
            try:
                req = urllib.request.Request(url, headers=self.headers)
                with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                    return json.loads(resp.read().decode("utf-8"))
            except Exception as exc:
                if attempt == 0:
                    time.sleep(1)
                    continue
                print(f"  API request failed: {exc}", file=sys.stderr)
        return None

    def search_papers(self, query: str, from_date: str, to_date: str, max_results: int) -> List[Dict[str, Any]]:
        papers: List[Dict[str, Any]] = []
        cursor = "*"
        while len(papers) < max_results:
            filters = [f"from_publication_date:{from_date}", f"to_publication_date:{to_date}", "type:article"]
            if self.topic_filter:
                filters.append(self.topic_filter)
            params = {
                "search": query,
                "filter": ",".join(filters),
                "sort": "publication_date:desc,relevance_score:desc",
                "per_page": min(self.per_page, max_results - len(papers)),
                "cursor": cursor,
                "select": SELECT_FIELDS,
            }
            if self.mailto:
                params["mailto"] = self.mailto
            if self.api_key:
                params["api_key"] = self.api_key

            data = self.api_get(f"{self.base_url}?{urllib.parse.urlencode(params)}")
            if not data:
                break

            batch = data.get("results", [])
            papers.extend(batch)
            cursor = (data.get("meta") or {}).get("next_cursor")
            if not batch or not cursor:
                break
            time.sleep(0.1)
        return papers

    def parse_paper(self, work: Dict[str, Any], track: str) -> Dict[str, Any]:
        def restore_abstract(inverted_index: Optional[Dict[str, List[int]]]) -> str:
            if not inverted_index:
                return ""
            positions = [(idx, word) for word, indexes in inverted_index.items() for idx in indexes]
            return " ".join(word for _, word in sorted(positions))

        loc = work.get("primary_location") or {}
        source = loc.get("source") or {}
        venue = source.get("display_name") or ""
        citations = work.get("cited_by_count", 0) or 0
        tier = self.scorer.get_tier(venue)

        return {
            "id": work.get("id") or "",
            "doi": work.get("doi") or "",
            "title": work.get("display_name") or work.get("title") or "",
            "authors": [
                a.get("author", {}).get("display_name")
                for a in (work.get("authorships") or [])
                if a.get("author", {}).get("display_name")
            ],
            "publication_year": work.get("publication_year"),
            "publication_date": work.get("publication_date") or "",
            "venue": venue,
            "cited_by_count": citations,
            "abstract": restore_abstract(work.get("abstract_inverted_index")),
            "landing_page_url": loc.get("landing_page_url") or work.get("doi") or work.get("id") or "",
            "pdf_url": loc.get("pdf_url") or (work.get("open_access") or {}).get("oa_url") or "",
            "track": track,
            "score": self.scorer.calculate_score(venue, citations),
            "tier": tier,
            "status": "new",
            "recommended_at": None,
        }

    def is_relevant(self, paper: Dict[str, Any], track: str) -> bool:
        title_lower = (paper.get("title") or "").lower()
        text = f"{title_lower} {(paper.get('abstract') or '').lower()}"
        filters = self.config["filters"]
        if any(token in title_lower for token in filters.get("title_blacklist", [])):
            return False
        if any(token in (paper.get("venue") or "").lower() for token in filters.get("source_blacklist", [])):
            return False
        keywords = self.config["tracks"].get(track, {}).get("keywords", [])
        return any(re.search(rf"(?<![a-z0-9]){re.escape(keyword.lower())}(?![a-z0-9])", text) for keyword in keywords)


class PaperDatabase:
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.path = Path(config["_data_file"])
        self.scorer = VenueScorer(config)

    def load(self) -> List[Dict[str, Any]]:
        if not self.path.is_file():
            return []
        try:
            with self.path.open() as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            raise SystemExit(f"Failed to read database: {exc}")
        if isinstance(data, dict) and isinstance(data.get("papers"), list):
            return data["papers"]
        if isinstance(data, list):
            return data
        raise SystemExit("Invalid database format, expected an array of papers.")

    def save(self, data: List[Dict[str, Any]]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

    @staticmethod
    def paper_keys(paper: Dict[str, Any]) -> List[str]:
        keys = []
        for key in (paper.get("id"), paper.get("doi")):
            if key and key not in keys:
                keys.append(key)
        title = " ".join((paper.get("title") or "").lower().split())
        if title:
            keys.append(f"title:{title}|date:{paper.get('publication_date') or ''}")
        return keys

    def recalculate_scores(self, database: Iterable[Dict[str, Any]]) -> None:
        for paper in database:
            venue = paper.get("venue") or ""
            citations = paper.get("cited_by_count", 0) or 0
            paper["tier"] = self.scorer.get_tier(venue)
            paper["score"] = self.scorer.calculate_score(venue, citations)

    def merge(self, database: List[Dict[str, Any]], fetched: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], int, int]:
        by_key: Dict[str, Dict[str, Any]] = {}
        papers: List[Dict[str, Any]] = []
        for paper in database:
            keys = self.paper_keys(paper)
            if not keys:
                continue
            papers.append(paper)
            for key in keys:
                by_key[key] = paper

        added = 0
        updated = 0
        for paper in fetched:
            keys = self.paper_keys(paper)
            if not keys:
                continue
            old = next((by_key[key] for key in keys if key in by_key), None)
            if old is None:
                papers.append(paper)
                for key in keys:
                    by_key[key] = paper
                added += 1
                continue

            status = old.get("status", "new")
            recommended_at = old.get("recommended_at")
            tracks = [t.strip() for t in (old.get("track") or "").split(",") if t.strip()]
            if paper.get("track") and paper["track"] not in tracks:
                tracks.append(paper["track"])
            old.update(paper)
            old["status"] = status
            old["recommended_at"] = recommended_at
            old["track"] = ",".join(tracks)
            for key in keys:
                by_key[key] = old
            updated += 1

        return sorted(papers, key=lambda p: (p.get("publication_date") or "", p.get("score", 0)), reverse=True), added, updated


def main() -> int:
    parser = argparse.ArgumentParser(description="OpenAlex PaperDaily fetcher")
    parser.add_argument("--days", type=int, help="Search window in days")
    parser.add_argument("--max-results", type=int, help="Max OpenAlex items per track")
    parser.add_argument("--dry-run", action="store_true", help="Do not save changes to disk")
    args = parser.parse_args()

    config = load_config()
    days = args.days or int(config["openalex"]["default_days"])
    max_results = args.max_results or int(config["openalex"]["default_max_results"])
    today = date.today()
    from_day = today - timedelta(days=days - 1)

    fetcher = PaperFetcher(config)
    database = PaperDatabase(config)

    print(f"OpenAlex range: {from_day.isoformat()} to {today.isoformat()} ({days} days)")
    print(f"Database: {database.path}")
    print("Config: config.json")
    if not fetcher.mailto:
        print("Tip: set openalex.mailto or OPENALEX_MAILTO for OpenAlex polite pool access.")
    print()

    track_stats = []
    fetched: List[Dict[str, Any]] = []
    for track, track_config in config["tracks"].items():
        query = track_config["query"]
        works = fetcher.search_papers(query, from_day.isoformat(), today.isoformat(), max_results)
        papers = [fetcher.parse_paper(work, track) for work in works]
        papers = [paper for paper in papers if fetcher.is_relevant(paper, track)]
        track_stats.append((track, len(works), len(papers)))
        fetched.extend(papers)

    current = database.load()
    before = len(current)
    database.recalculate_scores(current)
    merged, added, updated = database.merge(current, fetched)

    tier1 = sum(1 for p in merged if p.get('tier') == 1)
    high_score = sum(1 for p in merged if (p.get('score', 0) or 0) >= 15)

    # ── Formatted summary ──
    HL = "━" * 16
    print()
    print(HL)
    print(f"📚 Monthly Fetch Report · {today.isoformat()}")
    print(HL)
    print(f"🔍 Range: {from_day.isoformat()} ~ {today.isoformat()} ({days} days)")
    print()
    print("📊 Results by Track")
    for track, total, filtered in track_stats:
        print(f"  {track:<4}  OpenAlex {total:>4}  ->  local filter {filtered:>4}")
    print()
    print("📈 Database Changes")
    print(f"  New {added}  |  Updated {updated}  |  Total {len(merged)}")
    print(f"  Tier 1: {tier1}  |  High-score (≥15): {high_score}")
    if args.dry_run:
        print()
        print("🧪 dry-run mode, not saved")
    else:
        database.save(merged)
    print(HL)

    return 0


if __name__ == "__main__":
    sys.exit(main())

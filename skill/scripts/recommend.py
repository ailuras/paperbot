#!/usr/bin/env python3
"""
Daily Paper Recommendation from scripts/papers.json based on strategy.

Strategy:
1. Quality slots prefer papers at or above the configured score threshold.
2. Remaining slots prefer papers inside the configured recent-publication window.
3. Each slot falls back to broader unrecommended papers if its preferred pool is empty.
"""

import argparse
import json
import os
import random
import sys
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional

from common import atomic_write_json, load_config


def load_database(data_file: str) -> Optional[List[Dict]]:
    if not os.path.isfile(data_file):
        return None
    try:
        with open(data_file) as f:
            data = json.load(f)
    except (json.JSONDecodeError, IOError) as exc:
        raise SystemExit(f"Failed to read database: {exc}")
    if isinstance(data, dict):
        data = data.get("papers")
    if not isinstance(data, list) or not data:
        return None
    return data

def save_database(data: List[Dict], data_file: str) -> bool:
    try:
        atomic_write_json(data_file, data)
        return True
    except IOError:
        return False

def parse_publication_date(paper: Dict) -> Optional[date]:
    value = paper.get("publication_date") or ""
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError:
        return None

def paper_key(paper: Dict) -> str:
    return paper.get("id") or paper.get("doi") or paper.get("title") or ""

def unrecommended(paper: Dict) -> bool:
    return paper.get("status") != "recommended" and not paper.get("recommended_at")


def is_recent(paper: Dict, cutoff: date) -> bool:
    pub_date = parse_publication_date(paper)
    return pub_date is not None and pub_date >= cutoff

SEPARATOR = "·· ·· ··"
HEADER_LINE = "━" * 16

def format_output(selected_with_reason: List[tuple], data: List[Dict], config: Dict[str, Any]) -> str:
    today = datetime.now().strftime("%Y-%m-%d")
    rec_config = config.get("recommendation", {})
    include_ai_reading = rec_config.get("include_ai_reading_placeholder", True)
    recent_days = int(rec_config.get("recent_days", 30))
    lines = [
        HEADER_LINE,
        f"📬 Daily Papers · {today}",
        HEADER_LINE,
    ]

    for i, (p, reason) in enumerate(selected_with_reason, 1):
        title = p.get("title", "No Title")
        author_list = p.get("authors", [])
        authors = ", ".join(author_list[:5]) + (", et al." if len(author_list) > 5 else "")
        venue = p.get("venue", "") or "OpenAlex"
        year = p.get("publication_year") or "?"
        citations = p.get("cited_by_count", 0) or 0
        score = p.get("score", 0) or 0
        abstract = p.get("abstract", "") or "(No abstract)"
        url = p.get("landing_page_url", "")
        pdf_url = p.get("pdf_url", "")
        track = p.get("track", "")
        tier = p.get("tier", 0)
        pub_date = p.get("publication_date", "")

        lines.append("")
        lines.append(f"📌 {reason}  [{track}]")
        lines.append(HEADER_LINE)
        lines.append(f"📄 **{title}**")
        lines.append(f"👤 {authors}")
        venue_line = f"📍 {venue} {year}  ·  Cited {citations}  ·  Score {score:.1f}"
        if tier > 0:
            venue_line += f"  ·  Tier {tier}"
        lines.append(venue_line)
        if pub_date:
            lines.append(f"🗓️ Published: {pub_date}")
        lines.append(f"📝 **Abstract**: {abstract}")
        if include_ai_reading:
            lines.append(f"🤖 **AI Reading**: [AI_READING]")
        if url:
            lines.append(f"🔗 {url}")
        if pdf_url:
            lines.append(f"📥 {pdf_url}")

        if i < len(selected_with_reason):
            lines.append("")
            lines.append(SEPARATOR)

    pending = sum(1 for p in data if unrecommended(p))
    high_threshold = float(rec_config.get("high_score_threshold", 5))
    high_quality = sum(1 for p in data if unrecommended(p) and (p.get("score", 0) or 0) >= high_threshold)
    recent_cutoff = date.today() - timedelta(days=recent_days)
    recent_pending = 0
    for p in data:
        if unrecommended(p) and is_recent(p, recent_cutoff):
            recent_pending += 1

    lines.append("")
    lines.append(HEADER_LINE)
    lines.append(f"📊 Pending: {pending} | High-quality: {high_quality} | Recent {recent_days}d: {recent_pending}")

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Daily Paper Recommendation")
    parser.add_argument("--dry-run", action="store_true", help="Do not update file status")
    args = parser.parse_args()

    config = load_config()
    data_file = config["_data_file"]
    rec_config = config.get("recommendation", {})
    daily_count = max(0, int(rec_config.get("daily_count", 3)))
    quality_slots = max(0, int(rec_config.get("quality_slots", 1)))
    quality_slots = min(quality_slots, daily_count)
    high_threshold = float(rec_config.get("high_score_threshold", 5))
    recent_days = int(rec_config.get("recent_days", 30))

    data = load_database(data_file)
    if data is None:
        print("📂 No paper database found. Please run fetch_papers.py first.")
        return 0

    pending = [p for p in data if unrecommended(p)]
    if not pending:
        print("📭 No more papers to recommend. All historical papers have been read.")
        return 0

    # Prepare pools
    recent_cutoff = date.today() - timedelta(days=recent_days)
    recent_pending = [
        p for p in pending
        if is_recent(p, recent_cutoff)
    ]
    high_score_pending = [p for p in pending if (p.get("score", 0) or 0) >= high_threshold]

    exclude_ids = set()
    selected_with_reason = []

    def pop_random(pool: List[Dict]) -> Optional[Dict]:
        valid = [p for p in pool if paper_key(p) not in exclude_ids]
        if not valid:
            return None
        return random.choice(valid)

    # ==== Quality Priority Slots ====
    for _ in range(quality_slots):
        px = pop_random(high_score_pending)
        if px:
            selected_with_reason.append((px, f"💎 High-Quality Selection (>= {high_threshold:g} score)"))
        else:
            px = pop_random(recent_pending)
            if px:
                selected_with_reason.append((px, f"📅 Alternative Selection (Recent {recent_days} days)"))
            else:
                px = pop_random(pending)
                if px:
                    selected_with_reason.append((px, "🎲 Alternative Selection (Historical)"))
        if px:
            exclude_ids.add(paper_key(px))

    # ==== Recency Priority Slots ====
    while len(selected_with_reason) < daily_count:
        px = pop_random(recent_pending)
        if px:
            selected_with_reason.append((px, f"📅 Recent Release (Last {recent_days} days)"))
            exclude_ids.add(paper_key(px))
        else:
            px = pop_random(pending)
            if px:
                selected_with_reason.append((px, "🎲 Random Exploration (Historical)"))
                exclude_ids.add(paper_key(px))
            else:
                break

    # Output
    print(format_output(selected_with_reason, data, config))

    # Save status
    if not args.dry_run and selected_with_reason:
        now = datetime.now().isoformat()
        for (p, _) in selected_with_reason:
            p["status"] = "recommended"
            p["recommended_at"] = now
        save_database(data, data_file)

    return 0

if __name__ == "__main__":
    sys.exit(main())

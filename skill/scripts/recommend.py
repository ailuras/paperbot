#!/usr/bin/env python3
"""
Daily Paper Recommendation from scripts/papers.json based on strategy.

Strategy:
1. First paper (Quality Priority): Randomly select 1 paper with >= 5 score. If none, pick from last 30 days. If still none, random.
2. Second & Third paper (Recency Priority): Randomly select 2 papers from the last 30 days. If insufficient, fallback to random history.
"""

import argparse
import json
import os
import random
import sys
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List, Optional

SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_ROOT = SCRIPT_DIR.parent
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


CONFIG = load_config()
DATA_FILE = CONFIG["_data_file"]

def load_database() -> Optional[List[Dict]]:
    if not os.path.isfile(DATA_FILE):
        return None
    try:
        with open(DATA_FILE) as f:
            data = json.load(f)
    except (json.JSONDecodeError, IOError):
        return None
    if isinstance(data, dict):
        data = data.get("papers")
    if not isinstance(data, list) or not data:
        return None
    return data

def save_database(data: List[Dict]) -> bool:
    try:
        with open(DATA_FILE, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
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

SEPARATOR = "·· ·· ··"
HEADER_LINE = "━" * 16

def format_output(selected_with_reason: List[tuple], data: List[Dict]) -> str:
    today = datetime.now().strftime("%Y-%m-%d")
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
        lines.append(f"🤖 **AI Reading**: [AI_READING]")
        if url:
            lines.append(f"🔗 {url}")
        if pdf_url:
            lines.append(f"📥 {pdf_url}")

        if i < len(selected_with_reason):
            lines.append("")
            lines.append(SEPARATOR)

    pending = sum(1 for p in data if unrecommended(p))
    high_quality = sum(1 for p in data if unrecommended(p) and (p.get("score", 0) or 0) >= 5)
    thirty_days_ago = date.today() - timedelta(days=30)
    recent_pending = sum(
        1 for p in data
        if unrecommended(p)
        and parse_publication_date(p) is not None
        and parse_publication_date(p) >= thirty_days_ago
    )

    lines.append("")
    lines.append(HEADER_LINE)
    lines.append(f"📊 Pending: {pending} | High-quality: {high_quality} | Recent 30d: {recent_pending}")

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Daily Paper Recommendation")
    parser.add_argument("--dry-run", action="store_true", help="Do not update file status")
    args = parser.parse_args()

    data = load_database()
    if data is None:
        print("📂 No paper database found. Please run fetch_papers.py first.")
        return 0

    pending = [p for p in data if unrecommended(p)]
    if not pending:
        print("📭 No more papers to recommend. All historical papers have been read.")
        return 0

    # Prepare pools
    thirty_days_ago = date.today() - timedelta(days=30)
    recent_pending = [
        p for p in pending
        if parse_publication_date(p) is not None and parse_publication_date(p) >= thirty_days_ago
    ]
    high_score_pending = [p for p in pending if (p.get("score", 0) or 0) >= 5]

    exclude_ids = set()
    selected_with_reason = []

    def pop_random(pool: List[Dict]) -> Optional[Dict]:
        valid = [p for p in pool if paper_key(p) not in exclude_ids]
        if not valid:
            return None
        return random.choice(valid)

    # ==== Slot 1: Quality Priority ====
    p1 = pop_random(high_score_pending)
    if p1:
        selected_with_reason.append((p1, "💎 High-Quality Selection (>= 5 score)"))
        exclude_ids.add(paper_key(p1))
    else:
        p1 = pop_random(recent_pending)
        if p1:
            selected_with_reason.append((p1, "📅 Alternative Selection (Recent 30 days)"))
            exclude_ids.add(paper_key(p1))
        else:
            p1 = pop_random(pending)
            if p1:
                selected_with_reason.append((p1, "🎲 Alternative Selection (Historical)"))
                exclude_ids.add(paper_key(p1))

    # ==== Slot 2 & 3: Recency Priority ====
    for _ in range(2):
        px = pop_random(recent_pending)
        if px:
            selected_with_reason.append((px, "📅 Recent Release (Last 30 days)"))
            exclude_ids.add(paper_key(px))
        else:
            px = pop_random(pending)
            if px:
                selected_with_reason.append((px, "🎲 Random Exploration (Historical)"))
                exclude_ids.add(paper_key(px))

    # Output
    print(format_output(selected_with_reason, data))

    # Save status
    if not args.dry_run and selected_with_reason:
        now = datetime.now().isoformat()
        for (p, _) in selected_with_reason:
            p["status"] = "recommended"
            p["recommended_at"] = now
        save_database(data)

    return 0

if __name__ == "__main__":
    sys.exit(main())

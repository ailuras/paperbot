---
name: paperdaily
description: Use this skill whenever the user wants to fetch, filter, score, recommend, or explain academic papers from OpenAlex, especially for daily paper reading workflows, SMT/SAT/CP or other configurable research domains, paper recommendation databases, venue/citation scoring, or AI-generated reading guides. This skill should be used even when the user asks casually for a "paper bot", "daily papers", "OpenAlex recommendations", "论文日报", "每日读论文", or wants to customize paper discovery criteria.
---

# PaperDaily

PaperDaily is an OpenAlex-powered paper discovery workflow. It uses deterministic scripts for fetching and recommending papers, and uses the assistant for configuration, interpretation, and reading guidance.

## When To Use

Use this skill when the user wants to:

- Fetch new academic papers from OpenAlex.
- Maintain a local `papers.json` database.
- Score papers using venue tiers and citation impact.
- Recommend a daily reading list.
- Customize domains, keywords, venue tiers, scoring rules, or recommendation strategy.
- Generate AI reading notes from recommended papers.

## Repository Layout

- `scripts/fetch.py`: Fetches OpenAlex works, filters them locally, scores them, and merges them into the database.
- `scripts/recommend.py`: Selects daily papers from the local database and marks them as recommended unless `--dry-run` is used.
- `examples/config.example.json`: Configuration template. Copy to `~/.openclaw/workspace/paperdaily/config.json` and customize.
- `examples/papers.sample.json`: Minimal database schema example.
- `references/scoring.md`: Explanation of the scoring system.
- `references/openalex.md`: OpenAlex setup notes.

## Data Directory

Scripts auto-detect the data directory:

1. If `../data/` exists relative to the skill root (repo layout) → use that
2. Otherwise → `~/.openclaw/workspace/paperdaily/` (OpenClaw workspace)

Config and database:

- `config.json` — Runtime configuration (copy from `examples/config.example.json`)
- `papers.json` — Local paper database (auto-created on first fetch)

## Default Workflow

1. Copy `examples/config.example.json` to `~/.openclaw/workspace/paperdaily/config.json` and customize.
2. For a new setup, fetch the last year of papers:

```bash
python3 scripts/fetch.py --days 365 --max-results 2000
```

3. Run a dry-run fetch before saving large routine updates:

```bash
python3 scripts/fetch.py --dry-run
```

4. Fetch and save routine updates:

```bash
python3 scripts/fetch.py
```

This creates `papers.json` in the data directory automatically on first run if it does not exist.

5. Preview recommendations:

```bash
python3 scripts/recommend.py --dry-run
```

6. Recommend and mark papers as read/recommended:

```bash
python3 scripts/recommend.py
```

## Configuration Rules

PaperDaily is configured via `~/.openclaw/workspace/paperdaily/config.json`. Copy `examples/config.example.json` as a starting point, then edit the JSON fields to customize behavior.

Important configurable sections:

- `data_file`: Local paper database path.
- `openalex.mailto`: User email for OpenAlex polite pool access.
- `openalex.topic_filter`: OpenAlex field/topic filter.
- `tracks`: Research domains, OpenAlex search queries, and local relevance keywords.
- `filters`: Blacklists for artifacts and noisy venues.
- `scoring.tiers`: Venue tier points, acronyms, and full venue phrases.
- `scoring.citation_breakpoints`: Diminishing-return citation scoring.
- `scoring.max_citation_points`: Maximum citation contribution to the final score.
- `recommendation.daily_count`: Number of papers to recommend each run.
- `recommendation.quality_slots`: Number of slots that prefer high-score papers first.
- `recommendation.high_score_threshold`: Minimum score for the quality pool.
- `recommendation.recent_days`: Publication-date window for recent-paper selection.
- `recommendation.include_ai_reading_placeholder`: Whether to emit `[AI_READING]` for assistant-generated notes.

## Recommendation Logic

The default recommender selects 3 papers:

- First slot: random unrecommended paper with score >= `high_score_threshold`.
- Remaining slots: random unrecommended papers from the recent window.
- Fallback: if a preferred pool is empty, select from the broader unrecommended database.

The script preserves `status` and `recommended_at` during fetch merges so reading history is not overwritten by OpenAlex updates.

## AI Reading Guide

If `include_ai_reading_placeholder` is enabled, recommendation output includes:

```text
AI reading: [AI_READING]
```

When presenting results to the user, replace `[AI_READING]` with a concise reading guide based on the title, abstract, venue, and track.

Use this format:

```text
AI reading: This paper is worth reading because <main reason>. Focus on <specific method/result/claim>. It is most relevant if you care about <domain connection>.
```

Keep the guide factual. Do not claim details that are not supported by the abstract or metadata.

## Common Tasks

### Add A New Research Domain

Edit the `tracks` section in `~/.openclaw/workspace/paperdaily/config.json`:

```json
"FormalMethods": {
  "query": "\"formal verification\" OR \"model checking\"",
  "keywords": ["formal verification", "model checking", "temporal logic"]
}
```

Then run:

```bash
python3 scripts/fetch.py --dry-run
```

### Tune Scoring

Change `scoring.tiers` for venue reputation and `scoring.citation_breakpoints` for citation impact. Venue tiers should reflect the user's reading priorities, not a universal ranking.

### Use A Private Database Path

Set:

```json
"data_file": "~/paperdaily/papers.json"
```

This keeps private reading state outside the skill repository.

## Safety

- Do not commit private email addresses, API keys, or local paths.
- Prefer `--dry-run` before fetches that may create many database changes.

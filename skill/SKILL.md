---
name: paperdaily
description: Use this skill when the user wants daily academic paper recommendations, OpenAlex paper fetching, local paper database maintenance, or concise AI reading guidance for papers. Trigger for requests like "daily papers", "paper bot", "recommend papers", "fetch papers", "update my paper database", or paper discovery workflows around SMT/SAT/CP and related research areas.
---

# PaperDaily

PaperDaily maintains a local paper database and recommends papers for daily reading. The scripts do deterministic fetching, filtering, scoring, database updates, and recommendation selection. The assistant should run the scripts, explain results, and write factual reading guidance from paper metadata and abstracts.

## When To Use

Use this skill when the user wants to:

- Fetch or update papers from OpenAlex.
- Preview or generate daily paper recommendations.
- Maintain the local `papers.json` paper database.
- Explain recommended papers or add concise AI reading notes.
- Adjust paper discovery behavior when the user explicitly asks to tune domains, scoring, filtering, or recommendation policy.

## Runtime Files

The skill expects runtime files under:

```text
~/.openclaw/workspace/paperdaily/
```

The important files are:

- `config.json`: Runtime configuration.
- `papers.json`: Local paper database, resolved from `data_file` in `config.json`.

Only the config file location is auto-detected. Other behavior comes from `config.json`; fields present there take priority, and missing fields use internal defaults. Do not explain or modify config details unless the user asks.

## Commands

Preview a fetch before writing database changes:

```bash
python3 scripts/fetch.py --dry-run
```

Fetch and save routine updates:

```bash
python3 scripts/fetch.py
```

Preview recommendations without marking papers as recommended:

```bash
python3 scripts/recommend.py --dry-run
```

Recommend papers and mark them as recommended:

```bash
python3 scripts/recommend.py
```

For large backfills, use explicit limits and preview first:

```bash
python3 scripts/fetch.py --days 365 --max-results 2000 --dry-run
```

## Agent Workflow

For recommendations:

1. Run `python3 scripts/recommend.py --dry-run` first unless the user explicitly asks to mark papers as recommended.
2. Present the selected papers clearly.
3. If the output contains `[AI_READING]`, replace it with a short factual guide based only on the title, abstract, venue, and track.
4. Only run `python3 scripts/recommend.py` without `--dry-run` when the user wants the selected papers marked as recommended.

For fetching:

1. Run `python3 scripts/fetch.py --dry-run` first for routine updates or any large search window.
2. Summarize per-track counts, new papers, updated papers, and total database size.
3. Only run the non-dry-run fetch when the user confirms or explicitly asks to save updates.

For configuration changes:

1. Modify `config.json` only when the user asks to tune paper discovery behavior.
2. Prefer small, targeted changes.
3. Run a dry-run fetch or recommendation after changes to verify the effect.

## AI Reading Notes

When replacing `[AI_READING]`, keep the guide concise and grounded:

```text
AI reading: This paper is worth reading because <main reason>. Focus on <specific method/result/claim>. It is most relevant if you care about <domain connection>.
```

Rules:

- Use only information supported by the title, abstract, venue, track, and metadata.
- Do not invent methods, results, datasets, or claims.
- If the abstract is missing or vague, say what can be inferred and keep the note cautious.

## Safety

- Prefer `--dry-run` before any operation that changes the database.
- Do not mark papers as recommended unless the user asks for a real recommendation run.
- Do not overwrite `config.json` or `papers.json` manually unless the user explicitly requests it.
- Do not expose private emails, API keys, local paths, or other secrets in user-facing summaries.

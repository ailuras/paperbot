# Add Test Suite Plan

## Context

PaperBot currently has zero tests. `pyproject.toml` lists `pytest>=8.0` as a dev dependency, but no test files exist. The project has grown to include CLI commands, HTTP API, database layer, email notifications, and external API integration — all untested.

## Goal

Establish a test directory with pytest, covering core modules with unit tests and CLI/API with integration tests. Use fixtures for isolated test environments.

## Approach

### 1. Directory Structure

```
tests/
├── conftest.py          # Shared fixtures
├── test_config.py       # Settings loading, defaults, validation
├── test_db.py           # SQLite CRUD, state transitions, notes
├── test_fetch.py        # Venue scoring, abstract parsing, relevance filter
├── test_recommend.py    # Recommendation algorithm, dedup, score threshold
├── test_mail.py         # Email body generation, BibTeX export
├── test_cli.py          # CLI command smoke tests
└── test_dashboard.py    # HTTP API endpoint tests
```

### 2. Test Infrastructure (conftest.py)

- `tmp_config()` fixture: Creates a temporary `config.json` with test tracks
- `tmp_db()` fixture: Creates an in-memory or temp-file SQLite database, calls `init_db()`
- `sample_paper()` fixture: Returns a realistic paper dict for reuse across tests
- Mock `httpx.Client` responses for OpenAlex API tests (using `respx` or `responses`)

### 3. Module Coverage

| Module | What to Test |
|--------|-------------|
| `config.py` | `load_config()` loads example template, default values populated, env overrides work |
| `db.py` | `upsert_papers` insert/update counts, `set_paper_status` transitions, `get_unread_papers` filtering, `list_papers` pagination/sort, `get_paper_note` round-trip, `get_stats` aggregation |
| `fetch.py` | `VenueScorer.get_tier()` acronym/phrase matching, blacklist, `citation_score()` breakpoint math, `_restore_abstract()` from inverted index, `_is_relevant()` keyword regex, `_dedupe_and_merge_tracks()` |
| `recommend.py` | `recommend_papers()` quality slot priority, recency fallback, exclude dedup, empty pool handling |
| `mail.py` | `_build_email_body()` HTML output contains paper data, `_paper_to_html()` badge rendering, `generateBibTeX()` output format |
| `cli.py` | Commands register without error, `init`/`fetch`/`recommend`/`mark`/`stats`/`history`/`serve` exist |
| `dashboard.py` | `make_handler` routes respond correctly, API endpoints return expected JSON shape |

### 4. Dependencies

Add to `pyproject.toml` `[project.optional-dependencies]`:
```
dev = ["pytest>=8.0", "pytest-asyncio>=0.23", "ruff>=0.5", "respx>=0.21"]
```

`respx` is chosen because the project already uses `httpx` (not `requests`).

### 5. Running Tests

```bash
uv run pytest tests/ -v
```

## Files to Create/Modify

- **New**: `tests/conftest.py`, `tests/test_*.py` (7 files)
- **Modify**: `pyproject.toml` — add `pytest-asyncio` and `respx` to dev deps

## Verification

1. `uv run pytest tests/ -v` — all tests pass
2. `uv run pytest tests/ --cov=paperbot --cov-report=term-missing` — coverage report (optional)
3. `ruff check tests/` — lint passes

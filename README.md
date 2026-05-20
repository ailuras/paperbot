# PaperBot

Daily paper recommendation for SMT / SAT / CP researchers.

## Project Structure

```
paperbot/
├── data/
│   └── config.json          # user-configurable tracks, scoring tiers, filters
├── src/paperbot/
│   ├── __init__.py
│   ├── cli.py               # typer CLI (recommend, fetch, mark, stats, ...)
│   ├── config.py            # pydantic settings loader
│   └── db.py                # SQLite layer (papers, recommendations, marks)
├── pyproject.toml
└── README.md
```

## Install

```bash
uv pip install -e .
```

## Usage

```bash
paperbot --help
paperbot recommend
paperbot fetch --days 45
paperbot mark <paper-id> read
paperbot stats
paperbot history
paperbot serve --port 8000
paperbot migrate
```

## Configuration

Edit `data/config.json` to customize:

- **tracks** — SMT, SAT, CP queries and keywords
- **scoring.tiers** — venue tiers with point weights
- **scoring.citation_breakpoints** — citation → score mapping
- **filters** — title / source / venue blacklist
- **recommendation** — daily count, quality slots, thresholds

Default data directory: `~/.paperbot/`

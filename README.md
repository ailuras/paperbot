# PaperBot

Daily paper recommendation for SMT / SAT / CP researchers.

## Project Structure

```
paperbot/
├── data/
│   └── config.json          # user-configurable tracks, scoring tiers, filters
├── src/paperbot/
│   ├── __init__.py
│   ├── cli.py               # typer CLI entry point
│   ├── config.py            # pydantic settings loader
│   ├── dashboard.py         # web dashboard (HTTP server + SPA)
│   ├── db.py                # SQLite layer (papers, recommendations, marks)
│   ├── fetch.py             # OpenAlex API fetcher
│   └── recommend.py         # recommendation engine
├── pyproject.toml
└── README.md
```

## Requirements

- Python >= 3.10
- [uv](https://docs.astral.sh/uv/)

## Install

```bash
uv pip install -e .
```

## Usage

### 推荐：`uv run`

不需要手动激活虚拟环境。

```bash
uv run paperbot --help
uv run paperbot recommend
uv run paperbot fetch --days 45
uv run paperbot mark <paper-id> read
uv run paperbot stats
uv run paperbot history
uv run paperbot serve --port 8765
uv run paperbot migrate
```

### 或者：先激活虚拟环境

```bash
source .venv/bin/activate
paperbot --help
paperbot recommend
# ...
```

## Configuration

Edit `data/config.json` to customize:

- **tracks** — SMT, SAT, CP queries and keywords
- **scoring.tiers** — venue tiers with point weights
- **scoring.citation_breakpoints** — citation → score mapping
- **filters** — title / source / venue blacklist
- **recommendation** — daily count, quality slots, thresholds

Default data directory: `~/.paperbot/`

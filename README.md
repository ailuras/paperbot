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

### Recommended: `uv run`

No need to activate the virtual environment manually:

```bash
# List all commands
uv run paperbot --help

# Show detailed options for a command
uv run paperbot serve --help
uv run paperbot fetch --help
```

### Command Cheatsheet

| Command     | Description                    | Common Options                |
|-------------|--------------------------------|-------------------------------|
| `fetch`     | Fetch papers from OpenAlex     | `--days 40` last 40 days      |
| `recommend` | Generate daily recommendations | `--count 3` number of picks   |
| `mark`      | Mark a paper status            | `--status read`               |
| `stats`     | Show database statistics       | —                             |
| `history`   | Show recent reads              | `--limit 10`                  |
| `serve`     | Start the web dashboard        | `--port 8765 --daemon`        |

### Examples

```bash
# Fetch papers from the last 40 days
uv run paperbot fetch --days 40

# Generate 3 daily recommendations
uv run paperbot recommend --count 3

# Start dashboard (foreground)
uv run paperbot serve --port 8765

# Start dashboard (background)
uv run paperbot serve --port 8765 --daemon

# Mark a paper as read
uv run paperbot mark "paper title" --status read

# View statistics
uv run paperbot stats
```

### Alternative: activate venv first

```bash
source .venv/bin/activate

# Now you can use paperbot directly
paperbot --help
paperbot fetch --days 40
paperbot serve --port 8765 --daemon
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

# PaperBot

Daily paper recommendation for researchers. Configurable tracks, dual-theme dashboard, translation, and PDF resolution.

## What's New in v0.3.0

- **Dynamic tracks** — tracks are no longer hardcoded; configure any research area in `config.json`
- **Dark / light theme** — modern academic editorial design with theme toggle
- **Paper translation** — DeepSeek API integration for Chinese translations (cached)
- **PDF resolution** — multi-source open-access PDF finder (OpenAlex → Unpaywall → arXiv → Semantic Scholar)
- **Audit logging** — all operations logged to SQLite and text file for cron debugging
- **Email diagnostics** — SMTP errors are now printed with detailed messages

## Project Structure

```
paperbot/
├── data/
│   ├── config.json.example    # configuration template (copy to config.json)
│   └── config.json            # your local config (gitignored)
├── src/paperbot/
│   ├── __init__.py
│   ├── audit.py               # operation audit logging
│   ├── cli.py                 # typer CLI entry point
│   ├── config.py              # pydantic settings loader
│   ├── dashboard.py           # web dashboard (HTTP server + SPA)
│   ├── db.py                  # SQLite layer (papers, recommendations, marks)
│   ├── fetch.py               # OpenAlex API fetcher
│   ├── mail.py                # email notifications (sendmail / SMTP)
│   ├── pdf_resolver.py        # open-access PDF URL resolver
│   ├── recommend.py           # recommendation engine
│   └── translate.py           # DeepSeek API translation
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

| Command | Description | Common Options |
|---------|-------------|----------------|
| `fetch` | Fetch papers from OpenAlex | `--days 40`, `--email` |
| `recommend` | Generate daily recommendations | `--count 3`, `--email` |
| `mark` | Mark a paper status | `--status read` |
| `stats` | Show database statistics | — |
| `history` | Show recent reads | `--limit 10` |
| `audit` | View operation audit log | `--stats`, `--limit 20` |
| `serve` | Start the web dashboard | `--port 8765 --daemon` |

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

# View audit log (useful for cron debugging)
uv run paperbot audit --stats
uv run paperbot audit --limit 10
```

### Dashboard Features

Open http://localhost:8765 in your browser:

- **Dual theme** — toggle dark / light mode (persisted in localStorage)
- **Dynamic track pills** — track distribution shown in header
- **Paper detail modal** — click any paper title to view details
- **Translate** — translate title and abstract to Chinese via DeepSeek API
- **PDF** — resolve and open open-access PDF
- **BibTeX** — one-click copy
- **Personal notes** — save notes per paper

### Translation

Requires `DEEPSEEK_API_KEY` environment variable:

```bash
export DEEPSEEK_API_KEY=your_key_here
```

Translations are cached in the database; the same paper is never translated twice.

### PDF Resolution

Click the **PDF** button on any paper. PaperBot tries these sources in order:

1. OpenAlex metadata (free)
2. Unpaywall API (free)
3. arXiv search (free)
4. Semantic Scholar (free)

Resolved PDF URLs are cached in the database.

### Email Notifications

PaperBot supports email notifications via **local sendmail** (default) or **SMTP**.

**Local sendmail** (no configuration needed):
```bash
paperbot recommend --email
paperbot fetch --email
```

**SMTP** (configure in `data/config.json`):
```json
"mail": {
  "smtp_host": "smtp.gmail.com",
  "smtp_port": 587,
  "smtp_user": "your-email@gmail.com",
  "smtp_password": "your-app-password",
  "from_addr": "your-email@gmail.com",
  "from_name": "PaperBot",
  "to_addrs": ["recipient@example.com"],
  "use_tls": true
}
```

Environment variable overrides: `SMTP_HOST`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM`.

### Scheduled Tasks (crontab)

PaperBot uses system crontab for periodic tasks.

```bash
# Daily recommendation at 8:00
0 8 * * * /path/to/paperbot recommend --email

# Monthly fetch on 1st at 8:00
0 8 1 * * /path/to/paperbot fetch --email
```

Current crontab:
```bash
crontab -l
```

### Audit Logging

All `recommend` and `fetch` operations are logged to both SQLite (`audit_logs` table) and `~/.paperbot/audit.log` text file. Use this to debug cron issues:

```bash
# View recent operations
paperbot audit --limit 10

# View summary statistics
paperbot audit --stats

# Tail the text log
tail -f ~/.paperbot/audit.log
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

Copy the template and edit:

```bash
cp data/config.json.example data/config.json
```

Edit `data/config.json` to customize:

- **tracks** — define your research areas (name, query, keywords, optional color)
- **scoring.tiers** — venue tiers with point weights
- **scoring.citation_breakpoints** — citation -> score mapping
- **filters** — title / source / venue blacklist
- **recommendation** — daily count, quality slots, thresholds
- **mail** — email sender config (sendmail or SMTP)

Track example with custom color:
```json
"tracks": {
  "SMT": {
    "query": "SMT solver OR satisfiability modulo theories",
    "keywords": ["smt", "solver", "z3"],
    "color": "#2563eb"
  }
}
```

If `color` is omitted, a distinct color is auto-generated for each track.

Default data directory: `~/.paperbot/`

# PaperDaily

OpenAlex-powered paper discovery toolkit — fetch, score, and recommend academic papers for your research domains.

## Quick Start

```bash
git clone git@github.com:Ailuras/PaperDaily.git
cd PaperDaily

# 1. Customize tracking domains
vim data/config.json

# 2. Fetch papers
python3 skill/scripts/fetch.py --days 365

# 3. Get daily recommendations
python3 skill/scripts/recommend.py --dry-run
```

## Project Layout

```
PaperDaily/
├── skill/                     # AI skill (install to OpenClaw workspace)
│   ├── SKILL.md               # Skill workflow docs
│   ├── scripts/
│   │   ├── fetch.py           # Fetch & score papers from OpenAlex
│   │   └── recommend.py       # Daily paper recommendation
│   ├── examples/
│   │   ├── config.example.json
│   │   └── papers.sample.json
│   └── references/
│       ├── scoring.md
│       └── openalex.md
├── data/                      # Your data (papers database is git-ignored)
│   ├── config.json            # Your personalized config
│   └── papers.json            # Local paper database (auto-created)
└── README.md
```

## Configuration

Edit `data/config.json` to customize:

- **tracks** — Research domains and keywords (default: SMT, SAT, CP)
- **scoring** — Venue tier points and citation scoring
- **recommendation** — Daily count, quality threshold, recency window
- **openalex** — API settings (set `mailto` for polite pool)

## AI Skill

Copy `skill/` to `~/.openclaw/workspace/skills/paperdaily/` to use with OpenClaw.

The copied skill looks for its default config at `~/.openclaw/workspace/paperdaily/config.json`. The database path is not guessed separately; it comes from `data_file` inside that config. After copying the skill, prepare both files:

```bash
mkdir -p ~/.openclaw/workspace/paperdaily
cp skill/examples/config.example.json ~/.openclaw/workspace/paperdaily/config.json
cp skill/examples/papers.sample.json ~/.openclaw/workspace/paperdaily/papers.json
```

Then edit `~/.openclaw/workspace/paperdaily/config.json`. Make sure `data_file` points to the intended database, for example:

```json
"data_file": "~/.openclaw/workspace/paperdaily/papers.json"
```

Without this config/database setup, the copied skill may fail with a missing `config.json` or database path.

Only the config file location is auto-detected. All other runtime settings come from `config.json`: fields present in the file take priority, and missing fields use the script's internal defaults.

Cron example for daily paper push:

```bash
openclaw cron add --name "PaperBot Daily" --cron "0 8 * * *" --tz Asia/Shanghai \
  --session main --system-event "Use paperdaily skill to recommend daily papers and push to chat"
```

## License

MIT

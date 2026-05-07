# PaperDaily

OpenAlex-powered paper discovery toolkit — fetch, score, and recommend academic papers for your research domains.

## Quick Start

```bash
git clone git@github.com:Ailuras/PaperDaily.git
cd PaperDaily
pip install -r requirements.txt  # only requests

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
├── data/                      # Your data (git-ignored except config)
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

Cron example for daily paper push:

```bash
openclaw cron add --name "PaperBot Daily" --cron "0 8 * * *" --tz Asia/Shanghai \
  --session main --system-event "使用 paperdaily skill 执行每日论文推荐并推送微信"
```

## License

MIT

# PaperBot

PaperBot is a research-paper toolkit in two parts that share one repository:

| Path | Component | Stack | Role |
|------|-----------|-------|------|
| [`server/`](server/) | PaperBot backend | Python (`uv` / `pyproject`) | Fetches papers from [OpenAlex](https://openalex.org), scores them against your interests, and delivers daily picks via web dashboard and email. |
| [`app/`](app/) | VellumX desktop app | Swift / SwiftUI (macOS 14+) | Native macOS client for importing, reading, and organizing papers. |

The two components were developed as separate repositories and merged here with
their full histories preserved. Each subproject keeps its own build tooling and
documentation:

- Backend: see [`server/README.md`](server/README.md)
- macOS app: see [`app/README.md`](app/README.md)

## Layout

```text
PaperBot/
├── server/   # Python backend (OpenAlex fetch, scoring, dashboard, email)
└── app/      # VellumX macOS app (SwiftPM project under app/app/)
```

# VellumX — Design

**Status:** working release. A native macOS rewrite of the original Python
`PaperBot` (now superseded). Implemented: OpenAlex fetching, venue/citation
scoring + daily recommendation, DeepSeek bilingual abstract translation with
local cache, multi-tier open-access PDF resolution, SQLite-backed paper store
with reading status + notes, automatic migration of legacy PaperBot data, a
two-column main window, and a menu bar with the day's top picks.

## 1. What VellumX is

A **native macOS menu bar app** that runs a daily academic-paper workflow:
discover → score/recommend → translate → read → track. It replaces the previous
Python+SQLite+web `PaperBot` while reusing its data (auto-migrated on first run).

Founding intent: collapse a multi-component Python pipeline + web dashboard into
a single resident, native app that is always one click away in the menu bar.

## 2. Architecture

```
OpenAlex API ──► OpenAlexFetcher ──► RecommendEngine + VenueScorer
                                            │
                                            ▼
   DeepSeekTranslator ◄──────────── PaperStore (SQLite, @MainActor)
   (bilingual abstracts, cached)            │
                                            ├─► ContentView (two-column main window)
   PdfResolver (OA fallback chain) ◄────────┴─► MenuBarExtra (today's top picks)
```

- **Native + resident**: a `MenuBarExtra` keeps the day's recommendations one
  click away; the main `WindowGroup` is the full reading/triage UI.
- **Single SQLite store** at `~/Documents/06-文献/VellumX/vellumx.db`
  (iCloud-syncable). No ORM — system `SQLite3` directly.
- **Zero third-party dependencies**: pure SwiftPM + system frameworks, so the
  Command Line Tools build works without Xcode.

## 3. Data & config

- **Config** (`ConfigManager`): `$PAPERBOT_CONFIG` → `~/.vellumx/config.json`
  (legacy `~/.paperbot/config.json`) → `data/config.json`. Holds tracks +
  keywords, scoring tiers, citation breakpoints, recommendation knobs, DeepSeek
  + OpenAlex settings.
- **Store** (`PaperStore`): SQLite at the iCloud path above, with first-run
  auto-migration from `PaperBot`/legacy paths.

## 4. Recommendation model

Papers are scored by **venue tier** (`ScoringConfig.tiers`) plus a
**citation-breakpoint** curve (diminishing points per citation up to a cap). The
engine fills `daily_count` slots, reserving `quality_slots` for high-tier venues
and respecting `high_score_threshold` and `recent_days`.

## 5. PDF resolution

Open-access PDF lookup is a fallback chain: OpenAlex → Unpaywall → arXiv →
Semantic Scholar (`PdfResolver`). The menu bar "Open PDF" action uses a
pre-resolved URL when present, otherwise resolves on demand.

## 6. Build phases (as rebuilt from PaperBot)

1. **Scaffold**: SwiftUI app, Info.plist, entitlements, ad-hoc signing, build script.
2. **Data layer**: SQLite `PaperStore` + legacy migration.
3. **Config**: `AppConfig` decode + multi-path resolution.
4. **Fetch + score**: OpenAlex fetcher, venue scorer, recommend engine.
5. **Translation**: DeepSeek translator with local cache.
6. **PDF**: multi-tier OA resolver.
7. **UI**: two-column main window + menu bar top picks.

## 7. Out of scope (for now)

- The retired Python server and web dashboard.
- Email/SMTP delivery (config fields exist, carried over from PaperBot; the
  native app surfaces recommendations in-app rather than by email).

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A native macOS (SwiftUI, macOS 14+) **menu bar academic literature assistant**.
Migrated and refactored from the original Python `PaperBot`. It fetches papers
(OpenAlex), scores/recommends them, translates abstracts (DeepSeek), resolves
open-access PDFs, and manages reading status + notes.

All Swift source lives under [app/Sources/VellumX/](app/Sources/VellumX/).

## Build & run

The Swift package lives under `app/`. The app is wrapped into a code-signed
`.app` bundle (needed for the menu bar UI + entitlements). Build the bundle:

```bash
cd app
./build-app.sh            # release (default); or ./build-app.sh debug
open ./VellumX.app
./make-dmg.sh             # package VellumX.app into a distributable .dmg
```

`build-app.sh` runs `swift build`, wraps the binary into `VellumX.app` with
[Info.plist](app/Info.plist) + [VellumX.entitlements](app/VellumX.entitlements),
then ad-hoc code-signs it. There is no test target.

## Configuration

There is **no external config file**. `ConfigManager.effectiveConfig`
([Config.swift](app/Sources/VellumX/Config.swift)) builds the `AppConfig`
in-memory from three layers:

1. `AppConfig.builtin` ([ConfigDefaults.swift](app/Sources/VellumX/ConfigDefaults.swift))
   — API base URLs, the citation-score curve, OpenAlex query defaults.
2. `MetadataStore` — the venue taxonomy (`venues`), tier point values
   (`tiers`), tracks/keywords, and citation curve.
3. `AppSettings` — personalization knobs (recommendation, OpenAlex params,
   translation), which win.

Venue→tier/abbreviation matching is done **solely** by `VenueScorer` from
`MetadataStore.venues` — there are no hidden built-in venues. The DeepSeek API
key for translation lives in the Keychain (set via Settings ▸ API), not config.

## Data

[PaperStore.swift](app/Sources/VellumX/PaperStore.swift) is a `@MainActor`
`ObservableObject` backed by **SQLite3** (system `import SQLite3`, no ORM), in
WAL mode. The DB lives at
`~/Library/Application Support/VellumX/vellumx.db` by default (kept local, not
iCloud Drive, so the WAL sidecar files can't desync). The folder is
user-relocatable via Settings ▸ General (`AppSettings.storageDirectory`);
`PaperStore.relocate` moves the file and repoints `MetadataStore` at it.
[MetadataStore.swift](app/Sources/VellumX/MetadataStore.swift) opens a second
connection to the *same* file for the paper taxonomy tables.

## Architecture

- [VellumXApp.swift](app/Sources/VellumX/VellumXApp.swift) — `@main`. A
  `WindowGroup` (main two-column UI) plus a `MenuBarExtra` showing the day's top
  picks. Shares one `PaperStore.shared`.
- [ContentView.swift](app/Sources/VellumX/ContentView.swift) — the macOS
  two-column UI (left: category/track filter; right: detail + bilingual abstract).
- [OpenAlexFetcher.swift](app/Sources/VellumX/OpenAlexFetcher.swift) — paper
  fetching from OpenAlex.
- [RecommendEngine.swift](app/Sources/VellumX/RecommendEngine.swift) +
  [VenueScorer.swift](app/Sources/VellumX/VenueScorer.swift) — scoring by venue
  tier + citation breakpoints; picks the daily recommendations.
- [DeepSeekTranslator.swift](app/Sources/VellumX/DeepSeekTranslator.swift) —
  DeepSeek API abstract translation with local caching.
- [PdfResolver.swift](app/Sources/VellumX/PdfResolver.swift) — multi-tier OA PDF
  resolution (OpenAlex → Unpaywall → arXiv → Semantic Scholar).
- [Models.swift](app/Sources/VellumX/Models.swift) — `Paper` and related types.

## Conventions

- Keep the dependency surface at zero: pure SwiftPM + system frameworks only
  (no Xcode project required — Command Line Tools build must keep working).
- `PaperStore` and `ConfigManager` are `@MainActor`; respect that when calling.
- Paper status is a plain string (`"recommended"`, `"read"`, `"starred"`, …)
  set via `store.setPaperStatus(id:status:)`.

# VellumX

VellumX is a native macOS menu bar academic literature assistant and reading
workflow client. It fetches papers, scores recommendations, translates
abstracts, resolves open-access PDFs, and keeps reading status and notes in a
local SQLite library.

## Highlights

- Menu bar daily recommendations with quick paper actions.
- Native two-column paper browser with filters, notes, and bilingual abstracts.
- Venue and citation based recommendation scoring.
- Editable academic rules for tracks, fields, tiers, venues, and scoring curves.
- Configurable translation providers with local cache.
- Multi-stage open-access PDF resolution.
- User-relocatable SQLite database.

## Build And Run

```bash
make run      # swift test, debug rebuild, codesign, relaunch
make build    # release bundle build
make check    # SwiftPM debug build + XCTest suite
make dmg      # package app/VellumX-<version>.dmg
make clean    # remove local build and packaging artifacts
make logs     # stream VellumX OS logs
```

The Swift package stays under `app/`. Run VellumX as a bundled, signed `.app`,
not as a bare SwiftPM executable.

Development builds prefer a local Apple Development signing identity. If macOS
asks for the login keychain password while building, that is `codesign`
requesting access to the private key; choose Always Allow for `codesign` to
avoid repeated build-time prompts.

Branch and worktree variants use separate app names, bundle IDs, and
Application Support directories. Canonical `main` builds use
`~/Library/Application Support/VellumX`; a variant such as `feat-pdf` uses
`~/Library/Application Support/VellumX-feat-pdf`.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Building](docs/BUILDING.md)
- [Release](docs/RELEASE.md)
- [Agent guide](AGENTS.md)

## Requirements

- macOS 14.0+
- Swift 6.0 compatible toolchain

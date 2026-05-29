# PaperBot macOS App

**Daily Paper Recommendations · Smart Filtering · Native macOS App**

`PaperBot` is a native macOS menu-bar helper application built entirely in Swift and SwiftUI. It automatically fetches academic papers from [OpenAlex](https://openalex.org) based on your custom research tracks, filters them by keywords, scores them via journal tiers and citation segments, and presents daily recommended picks in a sleek native interface.

---

## Quickstart

### 1. Build and Bundle
Compile the Swift executable, bundle it as a signed `.app` container, and sign it via ad-hoc signatures (terminal-friendly standalone compilation, no Xcode project file required):

```bash
cd app
./build-app.sh release
```

### 2. Configure
The app loads configuration matching your research directions, scoring weights, and DeepSeek translation credentials.
Copy the configuration template:

```bash
cp data/config.json.example ~/.paperbot/config.json
```

Edit `~/.paperbot/config.json` to customize your **tracks** (topics & query filters), **scoring weights**, and add your `DEEPSEEK_API_KEY` for inline translations.

### 3. Launch
Run the application:

```bash
open app/PaperBot.app
```

You will see the 📚 icon appear in your macOS status bar.

---

## Core Features

| Feature | Description |
|---------|-------------|
| **MenuBar Status Panel** | Quick-access panel exhibiting daily recommended papers, with immediate triggers to open Open-Access PDFs or tag reading states. |
| **Native Library SplitView** | Three-pane SwiftUI layout containing Library (Status & Tracks) $\rightarrow$ Sorted paper list (Score, citations, date) $\rightarrow$ Full detailed views. |
| **Smart Fetching** | Multithreaded queries to OpenAlex with automated invert-index abstract recovery, keyword strict boundary screening, and de-duplication track merges. |
| **Adaptive Scoring** | Automated calculation matching custom tiers (e.g. CAV, PLDI) with tiered citation additions, bounded by score caps. |
| **DeepSeek Translation** | Local cached Chinese title/abstract translations via DeepSeek completion endpoint. |
| **Fallback PDF Resolver** | Multi-source resolution chain (OpenAlex $\rightarrow$ Unpaywall $\rightarrow$ arXiv $\rightarrow$ Semantic Scholar). |
| **Personal Notes** | Markdown text editor built-in for every paper to record research insights, persisted dynamically in JSON. |

---

## File Structure

```
PaperBot/
├── README.md               # User manual
├── REBUILD.md              # Rebuild blueprint
├── data/
│   └── config.json.example # Template config
└── app/                    # Primary Swift application
    ├── Package.swift       # SwiftPM manifest
    ├── Info.plist          # Bundle configuration
    ├── PaperBot.entitlements # Outbound network client access permissions
    ├── build-app.sh        # Core terminal build pipeline script
    └── Sources/PaperBot/
        ├── PaperBotApp.swift # SwiftUI App Entry & MenuBarExtra
        ├── ContentView.swift # Main window UI layout
        ├── Config.swift      # Codable Configuration Loader
        ├── Models.swift      # Paper metadata entities
        ├── PaperStore.swift  # Local JSON Database
        ├── OpenAlexFetcher.swift # HTTP fetcher
        ├── RecommendEngine.swift # Daily recomendation engine
        ├── VenueScorer.swift # Peer review venue tier weights
        ├── DeepSeekTranslator.swift # Translation client
        └── PdfResolver.swift  # Layered PDF url finder
```

---

## License
MIT

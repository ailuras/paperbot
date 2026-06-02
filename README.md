# 📚 VellumX

VellumX is a native macOS Menubar academic literature assistant and smart reading workflow client.

Migrated, upgraded, and refactored from the original Python-based `PaperBot`, VellumX focuses on providing you with a minimalist, focused, and efficient daily academic paper recommendation, translation, web PDF analysis, and personal note asset management experience.

---

## ✨ Key Features

- **📬 Menubar Integration**: Click the status bar icon to view carefully selected recommended papers for the day and perform quick actions (open PDF, mark read, star) without opening the main window.
- **💻 macOS Native Two-Column Interface**: A native SwiftUI interface. The left sidebar handles category filtering (Recommendations, Favorites, Read, Custom Tracks), while the right main view displays paper details, bilingual (English/Chinese) abstracts, and your personal reading notes.
- **⚖️ Smart Recommendation & Scoring**: Recommends the highest-quality papers based on venue ratings, customized tier points, and an adjustable citation-scoring curve.
- **📜 Academic Rules Editor**: Manage your academic taxonomy directly within the app settings. Customize search tracks (queries & keywords), venue ratings (tier categorization), tier point values, and multi-segment citation curves.
- **⚡ AI Translation**: Integrates configurable translation providers for high-speed bilingual abstract translation with local SQLite caching. API keys are saved in the app settings file for friction-free local development, and you can monitor real-time connection status with a pulsing breathing light indicator.
- **🔍 Fallback PDF Resolver**: Intelligently resolves open-access PDF links across multiple stages (OpenAlex → Unpaywall → arXiv → Semantic Scholar).
- **📂 User-Relocatable Database**: Stored by default in Application Support (`~/Library/Application Support/VellumX/vellumx.db`). You can easily relocate the database via the settings panel with automatic data migration.

---

## ⚙️ Configuration Architecture

VellumX separates system preferences from academic data for clean data integrity:
1. **App Preferences (`settings.json`)**: Configured automatically under `~/Library/Application Support/VellumX/settings.json` for UI preferences, recommendation counts, OpenAlex fetch constraints, and translation API keys.
2. **Academic Taxonomy & Venue Rules (SQLite)**: Stored inside `vellumx.db` (accessible via the "Rules" tab) for tracks, venues, scoring curves, and fields.

---

## 🛠️ Build & Run

VellumX is built purely using SwiftPM (Swift Package Manager) with **zero external dependencies** and can be compiled in the terminal without Xcode.

### 1. Compile & Build
The Swift package lives under `app/`. Run the following from the root directory or `app/` folder:
```bash
cd app
./build-app.sh release
```
This will compile the Swift binary and assemble it into a signed `VellumX.app` bundle.

### 2. Launch the App
```bash
open ./VellumX.app          # from inside the app/ directory
```

### 3. Package as a DMG
To package `VellumX.app` into a distributable DMG image:
```bash
./make-dmg.sh               # from inside the app/ directory
```

---

## 🖥️ Requirements
- macOS 14.0+
- Swift 5.9+ (Command Line Tools are sufficient)

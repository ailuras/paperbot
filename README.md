# 📰 VellumX

VellumX is a native macOS Menubar academic literature assistant and smart reading workflow client.

Migrated, upgraded, and refactored from the original `PaperBot`, it focuses on providing you with a minimalist, focused, and efficient daily academic paper recommendation, translation, web PDF analysis, and personal note asset management experience.

---

## ✨ Key Features

- **Menubar Integration**: Click the status bar icon to view 3 carefully selected recommended papers for the day.
- **macOS Native Two-Column Interface**: The left column handles category filtering (To Read, Favorites, Read, Track Categories), while the right column displays paper details and bilingual (Chinese/English) abstracts.
- **Smart Recommendation & Scoring**: Recommends the highest-quality academic achievements based on venue ratings and a custom scoring algorithm with citation breakpoints.
- **AI Translation**: Integrates the DeepSeek API for bilingual abstract translation, featuring high-speed local caching.
- **Multi-tiered Fallback PDF Parsing**: Intelligently detects Open Access PDFs (OpenAlex -> Unpaywall -> arXiv -> Semantic Scholar).
- **iCloud Sync & Automatic Database Migration**:
  - Data is stored by default at `~/Documents/06-文献/VellumX/vellumx.db`, fully supporting iCloud sync.
  - **Seamless Migration**: On first run, VellumX automatically detects and migrates your legacy `PaperBot` data (including historical notes, starred status, and translation caches).

---

## 🛠️ Build & Run

This project is built purely using SwiftPM (Swift Package Manager) and **can be compiled in the terminal without Xcode**.

### 1. Compile & Build
Run the following command in the root directory of the `VellumX` project:
```bash
./build-app.sh release
```
This will generate a signed `VellumX.app` application bundle in the current directory.

### 2. Launch the App
```bash
open ./VellumX.app
```
Once launched, you will see a `📚` icon in the macOS status bar (top-right corner). Click it to unfold today's academic dashboard.

---

## ⚙️ Configuration Notes

The configuration file is located at `~/.vellumx/config.json` (or compatibly read from the legacy path `~/.paperbot/config.json`). Please ensure the configuration file contains your:
- `DEEPSEEK_API_KEY` (or as an environment variable) for abstract translation.
- Academic tracks (`tracks`) and corresponding keywords (`keywords`) for fine-grained filtering.

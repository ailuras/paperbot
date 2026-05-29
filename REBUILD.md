# PaperBot macOS v2 — Rebuild Design Blueprint

**Status:** Proposed Design / Planning Phase (Archiving Python & CLI version)

---

## 1. Vision & Core Objectives
`PaperBot` 将从 Python CLI/SQLite/Web Dashboard 架构全面重组为**原生 macOS 应用程序（SwiftUI + SwiftData）**。我们保留原系统的智能抓取与过滤机制，但交互、推荐、渲染和本地持久化全部交由 macOS 系统层处理。

* **Menubar 状态栏常驻**: 提供无干扰的每日推荐卡片，点击即可查看今日论文、一键打开 OA PDF、一键标记为已读或收藏。
* **原生 macOS 体验**: 采用 SwiftUI 三栏/双栏经典布局展示论文库、搜索、状态分类以及编辑个人笔记。
* **轻量级无 Xcode 依赖编译**: 参照 DocsBot 模式，基于 Swift Package Manager (SPM) 与 `build-app.sh` 脚本在命令行快速编译、拼装 app 包和 codesign。

---

## 2. 系统架构

```
               [ OpenAlex API ]
                       ▲
                       │ (URLSession Fetch & Keyword Filter)
                       │
             Native Swift App (SwiftUI)
  ┌────────────────────┼───────────────────┐
  │                    ▼                   │
  │  SwiftData Storage (paperbot.store)    │
  │     ├─ Paper                           │
  │     ├─ TrackConfig                     │
  │     ├─ ScoringConfig                   │
  │     └─ RecommendationHistory           │
  │                                        │
  │  Service Layer                         │
  │     ├─ OpenAlexFetcher                 │
  │     ├─ VenueScorer (Scoring Rules)     │
  │     ├─ DeepSeekTranslator              │
  │     └─ PdfResolver (4-layer fallback)  │
  │                                        │
  │  UI Layer                              │
  │     ├─ MenuBarExtra (Today's Pick)     │
  │     ├─ MainWindow (Library SPA)        │
  │     └─ Settings (⌘,)                   │
  └────────────────────────────────────────┘
```

---

## 3. 工程与构建配置

我们采用零 `.xcodeproj` 重度依赖的 SPM 构建体系。

### 3.1 `app/Package.swift`
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PaperBot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PaperBot",
            path: "Sources/PaperBot"
        )
    ]
)
```

### 3.2 `app/Info.plist`
需要添加网络权限与后台运行相关的声明：
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.ailuras.paperbot</string>
    <key>CFBundleName</key>
    <string>PaperBot</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundleExecutable</key>
    <string>PaperBot</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/> <!-- 设为 true 允许应用作为 Menubar 助手在后台常驻而不在 Dock 中显示主图标 -->
</dict>
</plist>
```

---

## 4. SwiftData 核心数据模型设计 (`Models.swift`)

在 Swift 中使用 `@Model` 定义本地表结构，通过关系映射和自动持久化取代以往的 SQLite 手写 SQL 层。

```swift
import Foundation
import SwiftData

@Model
final class Paper {
    @Attribute(.unique) var id: String       // OpenAlex ID
    var doi: String?
    var title: String
    var authors: [String]
    var publicationDate: String
    var publicationYear: Int?
    var venue: String
    var venueAbbr: String
    var citedByCount: Int
    var abstract: String
    var landingPageUrl: String
    var pdfUrl: String?
    var track: String                        // 支持以逗号分隔的分类名称
    var score: Double
    var tier: Int
    var status: String                       // "pending", "recommended", "read", "starred", "skip"
    var changedAt: Date
    var note: String
    var titleZh: String
    var abstractZh: String
    
    init(id: String, title: String, venue: String, track: String) {
        self.id = id
        self.title = title
        self.venue = venue
        self.track = track
        self.authors = []
        self.publicationDate = ""
        self.citedByCount = 0
        self.abstract = ""
        self.landingPageUrl = ""
        self.score = 0.0
        self.tier = 0
        self.status = "pending"
        self.changedAt = Date()
        self.note = ""
        self.titleZh = ""
        self.abstractZh = ""
    }
}

@Model
final class TrackConfig {
    @Attribute(.unique) var name: String     // 例如 "SMT"
    var query: String                        // 传给 OpenAlex 的检索词
    var keywords: [String]                   // 本地硬匹配过滤关键词
    var colorHex: String                     // UI Badge 配色
    
    init(name: String, query: String, keywords: [String], colorHex: String = "#2563eb") {
        self.name = name
        self.query = query
        self.keywords = keywords
        self.colorHex = colorHex
    }
}
```

---

## 5. UI 架构设计

### 5.1 MenuBar 状态栏设计 (`MenuBarExtra`)
点击状态栏的 `📚`（或自定义 Icon）会弹出一个快捷卡片视图（`.menuBarExtraStyle(.window)`）：
* **今日精选**: 展示今日生成的 3 篇推荐论文标题、Track 标签和得分。
* **快捷控制**: 
  * 🖱️ 点击标题直接在主窗体查看详细摘要与中文翻译。
  * 🌐 点击 **"Read PDF"** 自动调用 `PdfResolver` 并通过默认浏览器拉起 PDF。
  * ✅ 一键标记为已读，或是 🌟 一键标记为收藏。
  * 🔄 **"Fetch & Recommend"** 快捷按钮：触发后台抓取并更新推荐。

### 5.2 MainWindow 主窗口设计 (`ContentView`)
主窗口采用典型的 macOS 原生分栏样式：
* **Sidebar (左栏)**: 
  * 快捷分类：今日推荐、待阅读 (Pending)、已收藏 (Starred)、已阅读 (Read)。
  * 学术轨道：显示所有 Tracks，并标记待阅读数量。
  * 状态指示：显示当前库中论文总数和近期统计。
* **Paper List (中栏)**: 
  * 显示当前分类下的论文列表卡片，支持以 `Score`、`Citations`、`Date` 排序。
  * 卡片上包含 Venue 缩写、分数徽章和 Track 徽章。
* **Detail View (右栏)**: 
  * 显示论文大标题、作者、刊物全称、原摘要。
  * **中英双语栏**: 支持一键 DeepSeek 翻译并并排对照显示。
  * **阅读笔记**: 内置文本框，可实时修改保存当前论文的研究笔记。
  * **PDF 按钮**: 高亮标记当前 PDF 地址状态（API 缓存/在线解析）。

---

## 6. 构建与移植路线图

为了分步稳妥地替换原有 Python 逻辑，计划按以下 6 个 Phase 依次进行：

### Phase 1: 项目骨架与编译脚本搭建
* 初始化 `app/` 文件夹。
* 创建 `Package.swift`、`Info.plist`、`app.entitlements`。
* 编写 `build-app.sh` 自动打包脚本，打通本地 ad-hoc codesign，确保 App 能够双击运行并有常驻 Menubar 结构。

### Phase 2: SwiftData 存储与基础 Scorer 实现
* 实现 `Models.swift` 数据实体。
* 编写 `VenueScorer.swift`：将 Python 中基于 Config JSON 文件的 Tier 积分和分段 Citation 算分规则移植到 Swift。

### Phase 3: OpenAlex 抓取与过滤机制移植
* 用 `URLSession` 实现 OpenAlexFetcher，支持从 OpenAlex 分页异步下载。
* 移植摘要倒排索引恢复算法、黑名单匹配算法、以及本地 tracks 关键词筛选逻辑。

### Phase 4: PDF 解析与翻译服务对接
* 移植 4 层 fallback PDF 查找服务：OpenAlex -> Unpaywall -> arXiv -> Semantic Scholar。
* 对接 DeepSeek Chat Completion 翻译服务，支持在后台缓存翻译字段到 SwiftData 中。

### Phase 5: Menubar 与主界面 (MenuBarExtra & MainWindow)
* 构建 Menubar 展示界面及 quick-actions。
* 实现主窗口的双栏浏览、搜索过滤、以及写笔记的交互功能。

### Phase 6: 清理 Python 遗留代码与最终打磨
* 确保功能完全移植并能够常驻运行后，从 Git 中删除 `src/` 下的原 Python 代码、CLI 逻辑以及 dashboard 相关模版。
* 编写最终的说明文档与配置引导。

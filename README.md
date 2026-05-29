# 📰 VellumX

VellumX 是一款 macOS 原生 Menubar（状态栏常驻）学术文献助手与智能阅读流客户端。

它由原来的 `PaperBot` 迁移并升级重构而来，专注于为您提供极简、专注且高效的每日学术论文推荐、翻译、网络 PDF 解析以及个人笔记资产管理。

---

## ✨ 核心特性

- **Menubar 状态栏常驻**：点击状态栏图标即可查看今日精心筛选的 3 篇推荐论文。
- **macOS 原生双栏界面**：左栏分类过滤（待读、收藏、已读、Track 分类），右栏呈现论文详请及中英双语摘要。
- **智能推荐与打分**：基于 Venue 评级与 Citation breakpoint 自定义积分算法，筛选最优质学术成果。
- **AI 智能翻译**：集成 DeepSeek API 进行双语摘要翻译，提供极速本地缓存。
- **多层降级 PDF 解析**：智能检测 Open Access PDF（OpenAlex -> Unpaywall -> arXiv -> Semantic Scholar）。
- **iCloud 同步与数据库自动迁移**：
  - 数据默认存储于 `~/Documents/06-文献/VellumX/vellumx.db`，完美支持 iCloud 同步。
  - **无缝平滑迁移**：首次运行将自动检测并同步迁移您的旧版 `PaperBot` 数据（包含历史笔记、星标状态及翻译缓存）。

---

## 🛠️ 编译与运行

本项目采用纯 SwiftPM (Swift Package Manager) 构建，**无需 Xcode 即可在终端编译**。

### 1. 编译与打包
在 `VellumX` 项目根目录下运行：
```bash
./build-app.sh release
```
这将在当前目录下生成已签名的 `VellumX.app` 应用程序包。

### 2. 启动应用
```bash
open ./VellumX.app
```
启动后，您会在 macOS 右上角状态栏看到 `📚` 图标，点击即可展开今日文献看板。

---

## ⚙️ 配置说明

配置文件存放于 `~/.vellumx/config.json`（或兼容读取旧版 `~/.paperbot/config.json`）。请确保配置文件中填入了您的：
- `DEEPSEEK_API_KEY`（或环境变量）用于摘要翻译。
- 学术轨道（tracks）和对应关键字（keywords）用于精细过滤。


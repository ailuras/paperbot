import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The standard macOS Settings window (⌘,), organized into tabs:
/// General (storage, menu bar), API (DeepSeek), Papers (recommendation +
/// OpenAlex + tracks), and Config File (advanced overrides).
struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("通用", systemImage: "gearshape") }
            APISettingsTab()
                .tabItem { Label("API", systemImage: "key") }
            PapersSettingsTab()
                .tabItem { Label("论文", systemImage: "doc.text.magnifyingglass") }
            ConfigFileTab()
                .tabItem { Label("配置文件", systemImage: "doc.badge.gearshape") }
        }
        .frame(width: 560, height: 480)
    }
}

// ── General ──────────────────────────────────────────────────────────────────

struct GeneralSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var store = PaperStore.shared

    @State private var pendingDir: URL?
    @State private var resultMessage: String?
    @State private var resultIsError = false

    private var currentDir: URL { settings.resolvedStorageDirectory }

    var body: some View {
        Form {
            Section("存储位置") {
                LabeledContent("当前位置") {
                    Text(currentDir.path)
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("更改…") { chooseFolder() }
                    if !settings.storageDirectory.isEmpty {
                        Button("恢复默认") { confirm(dir: AppSettings.defaultStorageDirectory) }
                    }
                }
                if let resultMessage {
                    Text(resultMessage)
                        .font(.caption)
                        .foregroundStyle(resultIsError ? .red : .green)
                }
                Text("数据库 vellumx.db 所在的文件夹。可放到 iCloud Drive 内以便同步。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("界面") {
                Toggle("在菜单栏显示", isOn: $settings.menuBarEnabled)
                Text("关闭后仅隐藏右上角状态栏图标，主窗口不受影响。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("更改存储位置", isPresented: Binding(
            get: { pendingDir != nil },
            set: { if !$0 { pendingDir = nil } }
        )) {
            Button("迁移现有数据库") { apply(migrate: true) }
            Button("仅切换，不迁移") { apply(migrate: false) }
            Button("取消", role: .cancel) { pendingDir = nil }
        } message: {
            Text("是否把当前数据库迁移到新位置？\n如目标位置已存在 vellumx.db，迁移会直接替换它。")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.directoryURL = currentDir
        if panel.runModal() == .OK, let dir = panel.url { confirm(dir: dir) }
    }

    private func confirm(dir: URL) {
        resultMessage = nil
        if dir.standardizedFileURL == currentDir.standardizedFileURL { return }
        pendingDir = dir
    }

    private func apply(migrate: Bool) {
        guard let dir = pendingDir else { return }
        pendingDir = nil
        switch store.relocate(to: dir, migrate: migrate) {
        case .ok(let db):
            resultIsError = false
            resultMessage = "已更新存储位置：\(db.deletingLastPathComponent().path)"
        case .failed(let msg):
            resultIsError = true
            resultMessage = msg
        }
    }
}

// ── API ──────────────────────────────────────────────────────────────────────

struct APISettingsTab: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("DeepSeek 翻译") {
                Toggle("启用摘要翻译", isOn: $settings.translateEnabled)
                SecureField("API Key", text: $settings.deepSeekAPIKey)
                Text("API Key 安全存储在系统钥匙串中，不写入配置文件。")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Base URL", text: $settings.deepSeekBaseURL)
                TextField("模型", text: $settings.deepSeekModel)
                TextField("目标语言", text: $settings.targetLanguage)
            }
        }
        .formStyle(.grouped)
    }
}

// ── Papers ─────────────────────────────────────────────────────────────────--

struct PapersSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("每日推荐") {
                Stepper("每日推荐数：\(settings.dailyCount)", value: $settings.dailyCount, in: 1...20)
                Stepper("质量优先槽位：\(settings.qualitySlots)", value: $settings.qualitySlots, in: 0...20)
                Stepper("高分阈值：\(settings.highScoreThreshold)", value: $settings.highScoreThreshold, in: 0...100)
                Stepper("新近窗口（天）：\(settings.recentDays)", value: $settings.recentDays, in: 1...365)
            }

            Section("OpenAlex 抓取") {
                TextField("联系邮箱 (mailto)", text: $settings.openAlexMailto)
                TextField("每页条数", value: $settings.perPage, format: .number)
                TextField("默认抓取天数", value: $settings.defaultDays, format: .number)
                TextField("最大结果数", value: $settings.defaultMaxResults, format: .number)
                TextField("主题过滤 (topic_filter)", text: $settings.topicFilter)
            }

            Section("研究方向 (Tracks)") {
                TracksEditor(tracks: $settings.tracks)
            }
        }
        .formStyle(.grouped)
    }
}

/// Add / edit / remove research tracks. Each track has a name, an OpenAlex
/// search query, and the keywords used to keep only relevant results.
struct TracksEditor: View {
    @Binding var tracks: [TrackPref]

    var body: some View {
        if tracks.isEmpty {
            Text("暂无方向。点击下方按钮添加。")
                .font(.caption).foregroundStyle(.secondary)
        }
        ForEach($tracks) { $track in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("名称", text: $track.name)
                        .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        tracks.removeAll { $0.id == track.id }
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                }
                TextField("搜索词 (query)", text: $track.query)
                    .textFieldStyle(.roundedBorder)
                TextField("关键词（逗号分隔）", text: keywordsBinding(for: $track))
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.vertical, 4)
        }
        Button {
            tracks.append(TrackPref(name: "新方向", query: "", keywords: []))
        } label: {
            Label("添加方向", systemImage: "plus")
        }
    }

    /// Edit a track's keyword array as a comma-separated string.
    private func keywordsBinding(for track: Binding<TrackPref>) -> Binding<String> {
        Binding(
            get: { track.wrappedValue.keywords.joined(separator: ", ") },
            set: { newValue in
                track.wrappedValue.keywords = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

// ── Config File ────────────────────────────────────────────────────────────--

struct ConfigFileTab: View {
    @EnvironmentObject private var settings: AppSettings

    private var resolvedPath: String {
        if !settings.advancedConfigPath.isEmpty { return settings.advancedConfigPath }
        return ConfigManager.shared.advancedConfigURL?.path ?? "（未设置）"
    }

    private var fileExists: Bool {
        guard let url = ConfigManager.shared.advancedConfigURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    var body: some View {
        Form {
            Section("高级配置文件") {
                LabeledContent("路径") {
                    Text(resolvedPath)
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("选择…") { choose() }
                    Button("打开") { open() }.disabled(!fileExists)
                    Button("在访达中显示") { reveal() }.disabled(!fileExists)
                    if !settings.advancedConfigPath.isEmpty {
                        Button("清除") { settings.advancedConfigPath = "" }
                    }
                }
                Text("可选。一个 JSON 文件，用于覆盖内置的评分规则 (scoring) 与过滤器 "
                     + "(filters)，例如完整的会议分级表。日常设置请在其他标签页中配置——"
                     + "可视化设置优先级更高。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            settings.advancedConfigPath = url.path
        }
    }

    private func open() {
        guard let url = ConfigManager.shared.advancedConfigURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func reveal() {
        guard let url = ConfigManager.shared.advancedConfigURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

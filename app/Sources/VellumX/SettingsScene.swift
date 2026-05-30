import SwiftUI
import AppKit

/// The standard macOS Settings window (⌘,). App-wide configuration only:
/// storage location for the database, and whether to show the menu bar item.
struct SettingsRootView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var store = PaperStore.shared

    /// A folder the user picked but hasn't confirmed how to apply yet.
    @State private var pendingDir: URL?
    @State private var resultMessage: String?
    @State private var resultIsError = false

    private var currentDir: URL { settings.resolvedStorageDirectory }

    /// Shared label-column width so both sections align on one trailing edge.
    private let labelWidth: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // ── Storage ──────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Label("存储位置", systemImage: "externaldrive")
                    .font(.title3).fontWeight(.semibold)
                Text("数据库 vellumx.db 所在的文件夹。可放到 iCloud Drive 内以便同步。")
                    .font(.caption).foregroundStyle(.secondary)

                // Fixed two-column layout: labels left, controls right,
                // sharing one trailing edge.
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("当前位置")
                            .frame(width: labelWidth, alignment: .leading)
                        Text(currentDir.path)
                            .font(.callout)
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GridRow {
                        Text("")
                            .frame(width: labelWidth, alignment: .leading)
                        HStack(spacing: 8) {
                            Button("更改…") { chooseFolder() }
                            if !settings.storageDirectory.isEmpty {
                                Button("恢复默认") { confirm(dir: AppSettings.defaultStorageDirectory) }
                            }
                            Spacer()
                        }
                    }
                }

                if let resultMessage {
                    Text(resultMessage)
                        .font(.caption)
                        .foregroundStyle(resultIsError ? .red : .green)
                }
            }

            Divider()

            // ── Interface ────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Label("界面", systemImage: "menubar.rectangle")
                    .font(.title3).fontWeight(.semibold)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("菜单栏")
                            .frame(width: labelWidth, alignment: .leading)
                        Toggle("在菜单栏显示", isOn: $settings.menuBarEnabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("关闭后仅隐藏右上角状态栏图标，主窗口不受影响。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 520, height: 360)
        // Migration prompt when a new folder is picked.
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
        if panel.runModal() == .OK, let dir = panel.url {
            confirm(dir: dir)
        }
    }

    private func confirm(dir: URL) {
        resultMessage = nil
        // No-op if it's the same folder we're already using.
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

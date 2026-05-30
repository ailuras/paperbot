import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ConfigFileTab: View {
    @State private var settings = AppSettings.shared

    private var resolvedPath: String {
        if !settings.advancedConfigPath.isEmpty { return settings.advancedConfigPath }
        return ConfigManager.shared.advancedConfigURL?.path ?? L10n.t(.notSet)
    }

    private var fileExists: Bool {
        guard let url = ConfigManager.shared.advancedConfigURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    var body: some View {
        Form {
            Section(L10n.t(.advancedConfigFile)) {
                LabeledContent(L10n.t(.path)) {
                    Text(resolvedPath)
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(L10n.t(.choose)) { choose() }
                    Button(L10n.t(.open)) { open() }.disabled(!fileExists)
                    Button(L10n.t(.revealInFinder)) { reveal() }.disabled(!fileExists)
                    if !settings.advancedConfigPath.isEmpty {
                        Button(L10n.t(.clear)) { settings.advancedConfigPath = "" }
                    }
                }
                Text(L10n.t(.advancedConfigHint))
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
        panel.prompt = L10n.t(.choose)
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

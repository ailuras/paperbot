import SwiftUI
import AppKit

struct GeneralSettingsTab: View {
    @State private var store = PaperStore.shared
    @State private var settings = AppSettings.shared

    @State private var pendingDir: URL?
    @State private var resultMessage: String?
    @State private var resultIsError = false

    private var currentDir: URL { settings.resolvedStorageDirectory }

    var body: some View {
        Form {
            Section(L10n.t(.storageLocation)) {
                LabeledContent(L10n.t(.currentLocation)) {
                    Text(currentDir.path)
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(L10n.t(.change)) { chooseFolder() }
                    if !settings.storageDirectory.isEmpty {
                        Button(L10n.t(.restoreDefault)) { confirm(dir: AppSettings.defaultStorageDirectory) }
                    }
                }
                if let resultMessage {
                    Text(resultMessage)
                        .font(.caption)
                        .foregroundStyle(resultIsError ? .red : .green)
                }
                Text(L10n.t(.storageHint))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.t(.interface)) {
                Toggle(L10n.t(.showInMenuBar), isOn: $settings.menuBarEnabled)
                Picker(L10n.t(.language), selection: $settings.language) {
                    Text("English").tag("en")
                    Text("中文").tag("zh")
                }
                Text(L10n.t(.menuBarHint))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert(L10n.t(.changeStorageTitle), isPresented: Binding(
            get: { pendingDir != nil },
            set: { if !$0 { pendingDir = nil } }
        )) {
            Button(L10n.t(.migrateDB)) { apply(migrate: true) }
            Button(L10n.t(.switchOnly)) { apply(migrate: false) }
            Button(L10n.t(.cancel), role: .cancel) { pendingDir = nil }
        } message: {
            Text(L10n.t(.migratePrompt))
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.t(.choose)
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
            resultMessage = "\(L10n.t(.storageUpdated)) \(db.deletingLastPathComponent().path)"
        case .failed(let msg):
            resultIsError = true
            resultMessage = msg
        }
    }
}

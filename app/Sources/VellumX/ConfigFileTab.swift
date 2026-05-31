import SwiftUI
import AppKit

struct ConfigFileTab: View {
    @State private var settings = AppSettings.shared

    private var fileURL: URL { settings.settingsFileURL }

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    var body: some View {
        Form {
            Section(L10n.t(.settingsFile)) {
                LabeledContent(L10n.t(.path)) {
                    Text(fileURL.path)
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(L10n.t(.open)) { NSWorkspace.shared.open(fileURL) }
                        .disabled(!fileExists)
                    Button(L10n.t(.revealInFinder)) {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                    .disabled(!fileExists)
                }
                Text(L10n.t(.settingsFileHint))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

import Foundation

/// App-wide user settings, persisted as JSON under Application Support
/// (`~/Library/Application Support/VellumX/settings.json`).
///
/// - `storageDirectory` is the folder that holds `vellumx.db`. Empty means
///   "use the default" (`~/Documents/06-文献/VellumX`), preserving the original
///   behavior so a fresh install just works.
/// - `menuBarEnabled` controls whether the status-bar item is shown (default on).
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var storageDirectory: String {
        didSet { save() }
    }
    @Published var menuBarEnabled: Bool {
        didSet { save() }
    }

    private let url: URL

    /// The folder where `vellumx.db` should live. Resolves the user override,
    /// falling back to the historical default location.
    var resolvedStorageDirectory: URL {
        if !storageDirectory.isEmpty {
            return URL(fileURLWithPath: (storageDirectory as NSString).expandingTildeInPath)
        }
        return AppSettings.defaultStorageDirectory
    }

    static var defaultStorageDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/06-文献/VellumX")
    }

    init(filename: String = "settings.json") {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VellumX")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent(filename)

        if let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            self.storageDirectory = stored.storageDirectory ?? ""
            self.menuBarEnabled = stored.menuBarEnabled ?? true
        } else {
            self.storageDirectory = ""
            self.menuBarEnabled = true
        }
    }

    private struct Stored: Codable {
        var storageDirectory: String?
        var menuBarEnabled: Bool?
    }

    private func save() {
        let stored = Stored(storageDirectory: storageDirectory, menuBarEnabled: menuBarEnabled)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(stored).write(to: url, options: .atomic)
    }
}

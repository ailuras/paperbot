import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The standard macOS Settings window (⌘,), organized into tabs:
/// General (storage, menu bar, language), API (DeepSeek), Papers
/// (recommendation + OpenAlex + tracks + venue ratings), and Config File.
struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(L10n.t(.general), systemImage: "gearshape") }
            APISettingsTab()
                .tabItem { Label(L10n.t(.api), systemImage: "key") }
            PapersSettingsTab()
                .tabItem { Label(L10n.t(.papers), systemImage: "doc.text.magnifyingglass") }
            ConfigFileTab()
                .tabItem { Label(L10n.t(.configFile), systemImage: "doc.badge.gearshape") }
        }
        .frame(width: 580, height: 520)
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

// ── API ──────────────────────────────────────────────────────────────────────

struct APISettingsTab: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section(L10n.t(.deepseekSection)) {
                Toggle(L10n.t(.enableTranslation), isOn: $settings.translateEnabled)
                SecureField("API Key", text: $settings.deepSeekAPIKey)
                Text(L10n.t(.apiKeyHint))
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Base URL", text: $settings.deepSeekBaseURL)
                TextField(L10n.t(.model), text: $settings.deepSeekModel)
                TextField(L10n.t(.targetLanguage), text: $settings.targetLanguage)
            }
        }
        .formStyle(.grouped)
    }
}

// ── Papers (ScrollView, not Form/List, to avoid NSTableView reentrancy) ───────

struct PapersSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox(L10n.t(.dailyRecommendations)) {
                    VStack(spacing: 10) {
                        stepperRow(L10n.t(.dailyCount), value: $settings.dailyCount, in: 1...20)
                        stepperRow(L10n.t(.qualitySlots), value: $settings.qualitySlots, in: 0...20)
                        stepperRow(L10n.t(.highScoreThreshold), value: $settings.highScoreThreshold, in: 0...100)
                        stepperRow(L10n.t(.recentWindow), value: $settings.recentDays, in: 1...365)
                    }
                    .padding(8)
                }

                GroupBox(L10n.t(.openAlexFetch)) {
                    VStack(alignment: .leading, spacing: 8) {
                        labeledField(L10n.t(.contactEmail), text: $settings.openAlexMailto)
                        labeledNumber(L10n.t(.perPage), value: $settings.perPage)
                        labeledNumber(L10n.t(.fetchDays), value: $settings.defaultDays)
                        labeledNumber(L10n.t(.maxResults), value: $settings.defaultMaxResults)
                        labeledField(L10n.t(.topicFilter), text: $settings.topicFilter)
                    }
                    .padding(6)
                }

                GroupBox(L10n.t(.interestsTracks)) {
                    TracksEditor(tracks: $settings.tracks)
                        .padding(6)
                }

                GroupBox(L10n.t(.venueRatings)) {
                    VenuesEditor(venues: $settings.venues)
                        .padding(6)
                }
            }
            .padding()
        }
    }

    /// Aligned row: label on the left, an editable numeric field plus a compact
    /// stepper on the right, so all rows line up and the value can be typed.
    private func stepperRow(_ label: String, value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("", value: clamped(value, to: range), format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .textFieldStyle(.roundedBorder)
            Stepper("", value: value, in: range)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    /// Keeps a typed value within the allowed range on commit.
    private func clamped(_ value: Binding<Int>, to range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).frame(width: 130, alignment: .leading)
            TextField("", text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func labeledNumber(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label).frame(width: 130, alignment: .leading)
            TextField("", value: value, format: .number).textFieldStyle(.roundedBorder)
        }
    }
}

/// Add / edit / remove research tracks. Plain VStack rows (not a List) so
/// mutating the array while editing can't trigger an NSTableView reentrancy.
struct TracksEditor: View {
    @Binding var tracks: [TrackPref]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if tracks.isEmpty {
                Text(L10n.t(.noTracks)).font(.caption).foregroundStyle(.secondary)
            }
            ForEach($tracks) { $track in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField(L10n.t(.name), text: $track.name)
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            tracks.removeAll { $0.id == track.id }
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                    TextField(L10n.t(.searchQuery), text: $track.query)
                        .textFieldStyle(.roundedBorder)
                    TextField(L10n.t(.keywordsCSV), text: keywordsBinding(for: $track))
                        .textFieldStyle(.roundedBorder)
                    Divider()
                }
            }
            Button {
                tracks.append(TrackPref(name: L10n.t(.newTrack), query: "", keywords: []))
            } label: { Label(L10n.t(.addTrack), systemImage: "plus") }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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

/// Add / edit / remove venue ratings (abbr, match phrase, tier). Plain rows.
struct VenuesEditor: View {
    @Binding var venues: [VenuePref]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if venues.isEmpty {
                Text(L10n.t(.noVenues)).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(L10n.t(.abbr)).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                Text(L10n.t(.matchPhrase)).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.t(.tier)).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                Spacer().frame(width: 24)
            }
            ForEach($venues) { $venue in
                HStack(spacing: 8) {
                    TextField(L10n.t(.abbr), text: $venue.abbr)
                        .textFieldStyle(.roundedBorder).frame(width: 70)
                    TextField(L10n.t(.matchPhrase), text: $venue.phrase)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    Picker("", selection: $venue.tier) {
                        ForEach(1...5, id: \.self) { Text("\(L10n.t(.tier)) \($0)").tag($0) }
                    }
                    .labelsHidden().frame(width: 90)
                    Button(role: .destructive) {
                        venues.removeAll { $0.id == venue.id }
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                venues.append(VenuePref(abbr: "", phrase: "", tier: 3))
            } label: { Label(L10n.t(.addVenue), systemImage: "plus") }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ── Config File ────────────────────────────────────────────────────────────--

struct ConfigFileTab: View {
    @EnvironmentObject private var settings: AppSettings

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

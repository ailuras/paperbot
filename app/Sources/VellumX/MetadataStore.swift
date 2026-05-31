import Foundation
import Observation
import SQLite3
import SwiftUI

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct FieldPref: Identifiable, Equatable {
    var id: String
    var name: String
    var color: String?
    var sortOrder: Int
}

struct TierPref: Identifiable, Equatable {
    var id: Int { rank }
    var rank: Int
    var name: String
    var points: Int
    var color: String?
    var sortOrder: Int
}

@MainActor
@Observable
final class MetadataStore {
    static let shared = MetadataStore()

    var topics: [TrackPref] = [] { didSet { persistIfReady(saveTopics) } }
    var fields: [FieldPref] = [] { didSet { persistIfReady(saveFields) } }
    var tiers: [TierPref] = [] { didSet { persistIfReady(saveTiers) } }
    var venues: [VenuePref] = [] { didSet { persistIfReady(saveVenues) } }
    var metadataVersion: Int = 0

    private var db: OpaquePointer?
    private var isLoading = false

    private init() {
        openDatabase()
        createTablesIfNeeded()
        seedFromSettingsIfNeeded()
        load()
    }

    var allFields: [String] {
        var names = fields.map(\.name).filter { !$0.isEmpty }
        for venue in venues {
            if let field = Self.normalizedField(venue.field), !names.contains(field) {
                names.append(field)
            }
        }
        if !names.contains(Self.othersField) {
            names.append(Self.othersField)
        }
        return names.sorted()
    }

    var allTiers: [Int] {
        let ranks = Set(tiers.map(\.rank) + venues.map(\.tier))
        return Array(ranks).sorted()
    }

    func field(forAbbr abbr: String) -> String {
        guard let venue = venues.first(where: { $0.abbr.caseInsensitiveCompare(abbr) == .orderedSame }) else {
            return Self.othersField
        }
        return Self.normalizedField(venue.field) ?? Self.othersField
    }

    func topicColor(_ topic: String) -> Color {
        color(named: topics.first(where: { $0.name == topic })?.color, default: .purple)
    }

    func fieldColor(_ field: String?) -> Color {
        let normalized = Self.normalizedField(field) ?? Self.othersField
        if normalized == Self.othersField {
            return color(named: fields.first(where: { $0.name == normalized })?.color, default: .gray)
        }
        return color(named: fields.first(where: { $0.name == normalized })?.color, default: .teal)
    }

    func tierColor(_ tier: Int) -> Color {
        color(named: tiers.first(where: { $0.rank == tier })?.color, default: tierDefaultColor(tier))
    }

    func color(forKey key: String, default defaultColor: LabelColor) -> Color {
        if let colorName = colorName(forKey: key) {
            return LabelColor.color(named: colorName) ?? defaultColor.color
        }
        return defaultColor.color
    }

    func setLabelColor(key: String, colorName: String?) {
        if key.hasPrefix("topic:") {
            let name = String(key.dropFirst("topic:".count))
            if let index = topics.firstIndex(where: { $0.name == name }) {
                topics[index].color = colorName
            }
        } else if key.hasPrefix("field:") {
            let name = String(key.dropFirst("field:".count))
            if let index = fields.firstIndex(where: { $0.name == name }) {
                fields[index].color = colorName
            } else {
                fields.append(FieldPref(id: UUID().uuidString, name: name, color: colorName, sortOrder: fields.count))
            }
        } else if key.hasPrefix("tier:"), let rank = Int(key.dropFirst("tier:".count)) {
            if let index = tiers.firstIndex(where: { $0.rank == rank }) {
                tiers[index].color = colorName
            } else {
                tiers.append(TierPref(rank: rank, name: "Tier \(rank)", points: Self.defaultPoints(for: rank), color: colorName, sortOrder: tiers.count))
            }
        }
        metadataVersion += 1
    }

    private func colorName(forKey key: String) -> String? {
        if key.hasPrefix("topic:") {
            let name = String(key.dropFirst("topic:".count))
            return topics.first(where: { $0.name == name })?.color
        }
        if key.hasPrefix("field:") {
            let name = String(key.dropFirst("field:".count))
            return fields.first(where: { $0.name == name })?.color
        }
        if key.hasPrefix("tier:"), let rank = Int(key.dropFirst("tier:".count)) {
            return tiers.first(where: { $0.rank == rank })?.color
        }
        return nil
    }

    private func color(named name: String?, default defaultColor: LabelColor) -> Color {
        LabelColor.color(named: name) ?? defaultColor.color
    }

    private func tierDefaultColor(_ tier: Int) -> LabelColor {
        switch tier {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        default: return .gray
        }
    }

    private func openDatabase() {
        let url = PaperStore.shared.dbURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            print("Error: Could not open metadata database at \(url.path)")
        } else {
            sqlite3_busy_timeout(db, 5000)
        }
    }

    private func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    /// Re-point this store at whatever `PaperStore.shared.dbURL` now resolves to.
    /// Called after the storage location changes (see `PaperStore.relocate`) so
    /// metadata and papers never end up split across two database files.
    func reopen() {
        closeDatabase()
        openDatabase()
        createTablesIfNeeded()
        seedFromSettingsIfNeeded()
        load()
    }

    private func createTablesIfNeeded() {
        let schema = """
        CREATE TABLE IF NOT EXISTS metadata_topics (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            query TEXT NOT NULL DEFAULT '',
            keywords_json TEXT NOT NULL DEFAULT '[]',
            color TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS metadata_fields (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            color TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS metadata_tiers (
            rank INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            points INTEGER NOT NULL,
            color TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS metadata_venue_rules (
            id TEXT PRIMARY KEY,
            abbr TEXT NOT NULL,
            phrase TEXT NOT NULL,
            exact INTEGER NOT NULL DEFAULT 0,
            field_name TEXT,
            tier_rank INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0
        );
        """

        var errorMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, schema, nil, nil, &errorMsg) != SQLITE_OK {
            let error = errorMsg.map { String(cString: $0) } ?? "unknown error"
            print("Error creating metadata tables: \(error)")
            sqlite3_free(errorMsg)
        }
    }

    private func seedFromSettingsIfNeeded() {
        guard countRows("metadata_topics") == 0,
              countRows("metadata_venue_rules") == 0,
              countRows("metadata_fields") == 0,
              countRows("metadata_tiers") == 0 else {
            return
        }

        let settings = AppSettings.shared
        isLoading = true
        topics = settings.tracks.isEmpty ? AppSettings.defaultTracks : settings.tracks
        venues = settings.venues.isEmpty ? AppSettings.defaultVenues : settings.venues
        fields = makeFields(from: venues, colors: settings.labelColors)
        tiers = makeTiers(from: venues, colors: settings.labelColors)
        for index in topics.indices {
            topics[index].color = settings.labelColors["topic:\(topics[index].name)"]
        }
        isLoading = false

        saveTopics()
        saveFields()
        saveTiers()
        saveVenues()
    }

    private func load() {
        isLoading = true
        topics = loadTopics()
        fields = loadFields()
        tiers = loadTiers()
        venues = loadVenues()
        isLoading = false
        metadataVersion += 1
    }

    private func persistIfReady(_ persist: () -> Void) {
        guard !isLoading else { return }
        persist()
        metadataVersion += 1
    }

    private func saveTopics() {
        replace(table: "metadata_topics") {
            let sql = "INSERT INTO metadata_topics (id, name, query, keywords_json, color, sort_order) VALUES (?, ?, ?, ?, ?, ?)"
            for (index, topic) in topics.enumerated() {
                let keywordsData = (try? JSONEncoder().encode(topic.keywords)) ?? Data("[]".utf8)
                let keywords = String(data: keywordsData, encoding: .utf8) ?? "[]"
                execute(sql, bindings: [
                    topic.id.uuidString,
                    topic.name,
                    topic.query,
                    keywords,
                    topic.color,
                    index
                ])
            }
        }
    }

    private func saveFields() {
        replace(table: "metadata_fields") {
            for (index, field) in fields.enumerated() {
                execute(
                    "INSERT INTO metadata_fields (id, name, color, sort_order) VALUES (?, ?, ?, ?)",
                    bindings: [field.id, field.name, field.color, index]
                )
            }
        }
    }

    private func saveTiers() {
        replace(table: "metadata_tiers") {
            for (index, tier) in tiers.enumerated() {
                execute(
                    "INSERT INTO metadata_tiers (rank, name, points, color, sort_order) VALUES (?, ?, ?, ?, ?)",
                    bindings: [tier.rank, tier.name, tier.points, tier.color, index]
                )
            }
        }
    }

    private func saveVenues() {
        replace(table: "metadata_venue_rules") {
            for (index, venue) in venues.enumerated() {
                execute(
                    "INSERT INTO metadata_venue_rules (id, abbr, phrase, exact, field_name, tier_rank, sort_order) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    bindings: [
                        venue.id.uuidString,
                        venue.abbr,
                        venue.phrase,
                        venue.exact == true ? 1 : 0,
                        Self.normalizedField(venue.field),
                        venue.tier,
                        index
                    ]
                )
            }
        }
    }

    private func replace(table: String, body: () -> Void) {
        sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
        sqlite3_exec(db, "DELETE FROM \(table)", nil, nil, nil)
        body()
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    private func execute(_ sql: String, bindings: [Any?]) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        for (index, value) in bindings.enumerated() {
            bind(value, to: Int32(index + 1), in: stmt)
        }
        sqlite3_step(stmt)
    }

    private func bind(_ value: Any?, to index: Int32, in stmt: OpaquePointer?) {
        switch value {
        case let value as String:
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        case let value as Int:
            sqlite3_bind_int(stmt, index, Int32(value))
        case let value as Bool:
            sqlite3_bind_int(stmt, index, value ? 1 : 0)
        case .none:
            sqlite3_bind_null(stmt, index)
        default:
            sqlite3_bind_null(stmt, index)
        }
    }

    private func countRows(_ table: String) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table)", -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    private func loadTopics() -> [TrackPref] {
        let sql = "SELECT id, name, query, keywords_json, color FROM metadata_topics ORDER BY sort_order, name"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [TrackPref] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = UUID(uuidString: columnString(stmt, 0)) ?? UUID()
            let name = columnString(stmt, 1)
            let query = columnString(stmt, 2)
            let keywordsRaw = columnString(stmt, 3)
            let keywordsData = keywordsRaw.data(using: .utf8) ?? Data("[]".utf8)
            let keywords = (try? JSONDecoder().decode([String].self, from: keywordsData)) ?? []
            let color = columnOptionalString(stmt, 4)
            rows.append(TrackPref(id: id, name: name, query: query, keywords: keywords, color: color))
        }
        return rows
    }

    private func loadFields() -> [FieldPref] {
        let sql = "SELECT id, name, color, sort_order FROM metadata_fields ORDER BY sort_order, name"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [FieldPref] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(FieldPref(
                id: columnString(stmt, 0),
                name: columnString(stmt, 1),
                color: columnOptionalString(stmt, 2),
                sortOrder: Int(sqlite3_column_int(stmt, 3))
            ))
        }
        return rows
    }

    private func loadTiers() -> [TierPref] {
        let sql = "SELECT rank, name, points, color, sort_order FROM metadata_tiers ORDER BY sort_order, rank"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [TierPref] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rank = Int(sqlite3_column_int(stmt, 0))
            rows.append(TierPref(
                rank: rank,
                name: columnString(stmt, 1),
                points: Int(sqlite3_column_int(stmt, 2)),
                color: columnOptionalString(stmt, 3),
                sortOrder: Int(sqlite3_column_int(stmt, 4))
            ))
        }
        return rows
    }

    private func loadVenues() -> [VenuePref] {
        let sql = "SELECT id, abbr, phrase, exact, field_name, tier_rank FROM metadata_venue_rules ORDER BY sort_order, abbr"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [VenuePref] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(VenuePref(
                id: UUID(uuidString: columnString(stmt, 0)) ?? UUID(),
                abbr: columnString(stmt, 1),
                phrase: columnString(stmt, 2),
                tier: Int(sqlite3_column_int(stmt, 5)),
                field: Self.normalizedField(columnOptionalString(stmt, 4)),
                exact: sqlite3_column_int(stmt, 3) == 1
            ))
        }
        return rows
    }

    private func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? ""
    }

    private func columnOptionalString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let raw = sqlite3_column_text(stmt, index) else { return nil }
        let value = String(cString: raw)
        return value.isEmpty ? nil : value
    }

    private func makeFields(from venues: [VenuePref], colors: [String: String]) -> [FieldPref] {
        let names = Set(venues.compactMap { Self.normalizedField($0.field) } + [Self.othersField])
        return names.sorted().enumerated().map { index, name in
            FieldPref(id: UUID().uuidString, name: name, color: colors["field:\(name)"], sortOrder: index)
        }
    }

    private func makeTiers(from venues: [VenuePref], colors: [String: String]) -> [TierPref] {
        let ranks = Set(venues.map(\.tier))
        return ranks.sorted().enumerated().map { index, rank in
            TierPref(
                rank: rank,
                name: "Tier \(rank)",
                points: Self.defaultPoints(for: rank),
                color: colors["tier:\(rank)"],
                sortOrder: index
            )
        }
    }

    private static func defaultPoints(for rank: Int) -> Int {
        AppSettings.tierPoints[rank] ?? max(1, 12 - 2 * rank)
    }

    private static let othersField = "Others"

    private static func normalizedField(_ field: String?) -> String? {
        guard let value = field?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value.caseInsensitiveCompare("Preprint") == .orderedSame ? "OT" : value
    }
}

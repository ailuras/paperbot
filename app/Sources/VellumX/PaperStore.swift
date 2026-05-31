import Foundation
import Observation
import SQLite3

/// SQLite needs to COPY bound Swift strings: a Swift String bridges to a C
/// pointer that is only valid for the duration of the bind call, so passing
/// SQLITE_STATIC (nil) leaves SQLite with a dangling pointer by the time
/// sqlite3_step runs — it then stores empty/garbage. SQLITE_TRANSIENT tells
/// SQLite to make its own copy.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
@Observable
class PaperStore: ObservableObject {
    var papers: [Paper] = []
    var paperVersion: Int = 0

    static let shared = PaperStore()

    private var db: OpaquePointer?

    var dbURL: URL {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        let targetDir = AppSettings.shared.resolvedStorageDirectory
        let targetDb = targetDir.appendingPathComponent("vellumx.db")

        try? fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: targetDb.path) {
            let oldDefaultDb = home.appendingPathComponent("Documents/06-文献/VellumX/vellumx.db")
            let paperBotDb = home.appendingPathComponent("Documents/06-文献/PaperBot/paperbot.db")
            if fileManager.fileExists(atPath: oldDefaultDb.path) {
                try? fileManager.copyItem(at: oldDefaultDb, to: targetDb)
            } else if fileManager.fileExists(atPath: paperBotDb.path) {
                try? fileManager.copyItem(at: paperBotDb, to: targetDb)
            } else {
                var legacyDir = home.appendingPathComponent(".paperbot")
                if let configDir = ConfigManager.shared.effectiveConfig.data_dir {
                    let expanded = (configDir as NSString).expandingTildeInPath
                    legacyDir = URL(fileURLWithPath: expanded)
                }
                let legacyDb = legacyDir.appendingPathComponent("paperbot.db")
                if fileManager.fileExists(atPath: legacyDb.path) {
                    try? fileManager.copyItem(at: legacyDb, to: targetDb)
                }
            }
        }

        return targetDb
    }

    private init() {
        openDatabase()
        createTablesIfNeeded()
        loadPapers()
    }

    private func openDatabase() {
        let url = dbURL
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            print("Error: Could not open database at \(url.path)")
        } else {
            print("Database opened at \(url.path)")
        }
    }

    private func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    enum RelocateResult {
        case ok(URL)
        case failed(String)
    }

    @discardableResult
    func relocate(to newDir: URL, migrate: Bool) -> RelocateResult {
        let fm = FileManager.default
        let currentDb = dbURL
        let destDb = newDir.appendingPathComponent("vellumx.db")

        do {
            try fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        } catch {
            return .failed("无法创建目录：\(error.localizedDescription)")
        }

        if currentDb.standardizedFileURL != destDb.standardizedFileURL, migrate {
            closeDatabase()
            do {
                if fm.fileExists(atPath: destDb.path) {
                    try fm.removeItem(at: destDb)
                }
                if fm.fileExists(atPath: currentDb.path) {
                    try fm.moveItem(at: currentDb, to: destDb)
                }
            } catch {
                openDatabase()
                return .failed("迁移失败：\(error.localizedDescription)")
            }
        } else if !migrate {
            closeDatabase()
        }

        AppSettings.shared.storageDirectory = newDir.path
        openDatabase()
        createTablesIfNeeded()
        loadPapers()
        // Repoint the metadata store at the new file too, otherwise its open
        // connection keeps writing the old database and the two diverge.
        MetadataStore.shared.reopen()
        return .ok(destDb)
    }

    private func createTablesIfNeeded() {
        let schema = """
        CREATE TABLE IF NOT EXISTS papers (
            id TEXT PRIMARY KEY,
            doi TEXT,
            title TEXT NOT NULL,
            authors TEXT,
            publication_date TEXT,
            venue TEXT,
            venue_abbr TEXT,
            cited_by_count INTEGER DEFAULT 0,
            abstract TEXT,
            landing_page_url TEXT,
            pdf_url TEXT,
            track TEXT,
            score REAL DEFAULT 0,
            tier TEXT,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS paper_states (
            paper_id TEXT PRIMARY KEY,
            status TEXT NOT NULL DEFAULT 'pending',
            changed_at TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS paper_notes (
            paper_id TEXT PRIMARY KEY,
            note TEXT NOT NULL DEFAULT '',
            updated_at TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS paper_translations (
            paper_id TEXT PRIMARY KEY,
            abstract_zh TEXT,
            updated_at TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS paper_pdfs (
            paper_id TEXT PRIMARY KEY,
            pdf_url TEXT NOT NULL,
            pdf_source TEXT,
            resolved_at TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS paper_topics (
            paper_id TEXT NOT NULL,
            topic_name TEXT NOT NULL,
            PRIMARY KEY (paper_id, topic_name)
        );
        """

        var errorMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, schema, nil, nil, &errorMsg) != SQLITE_OK {
            let error = errorMsg.map { String(cString: $0) } ?? "unknown error"
            print("Error creating tables: \(error)")
            sqlite3_free(errorMsg)
        }
        migratePaperTopicsIfNeeded()
    }

    func loadPapers() {
        let query = """
        SELECT p.id, p.doi, p.title, p.authors, p.publication_date, p.venue, p.venue_abbr,
               p.cited_by_count, p.abstract, p.landing_page_url, COALESCE(f.pdf_url, p.pdf_url) as pdf_url,
               COALESCE(NULLIF((
                   SELECT group_concat(topic_name, ', ')
                   FROM (
                       SELECT topic_name
                       FROM paper_topics
                       WHERE paper_id = p.id
                       ORDER BY topic_name
                   )
               ), ''), p.track) as track,
               p.score, p.tier, COALESCE(ps.status, 'pending') as status,
               COALESCE(ps.changed_at, datetime('now')) as changed_at,
               COALESCE(pn.note, '') as note, COALESCE(pt.abstract_zh, '') as abstract_zh
        FROM papers p
        LEFT JOIN paper_states ps ON p.id = ps.paper_id
        LEFT JOIN paper_notes pn ON p.id = pn.paper_id
        LEFT JOIN paper_translations pt ON p.id = pt.paper_id
        LEFT JOIN paper_pdfs f ON p.id = f.paper_id
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) != SQLITE_OK {
            print("Failed to prepare statement for loading papers")
            return
        }
        defer {
            sqlite3_finalize(stmt)
        }

        var loadedPapers: [Paper] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let doi = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let title = String(cString: sqlite3_column_text(stmt, 2))

            var authors: [String] = []
            if let authorsRaw = sqlite3_column_text(stmt, 3) {
                let authorsStr = String(cString: authorsRaw)
                if let data = authorsStr.data(using: .utf8) {
                    authors = (try? JSONDecoder().decode([String].self, from: data)) ?? []
                }
            }

            let pubDate = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            let venue = String(cString: sqlite3_column_text(stmt, 5))
            let venueAbbr = String(cString: sqlite3_column_text(stmt, 6))
            let citedCount = Int(sqlite3_column_int(stmt, 7))
            let abstract = String(cString: sqlite3_column_text(stmt, 8))
            let landingPage = String(cString: sqlite3_column_text(stmt, 9))
            let pdfUrl = sqlite3_column_text(stmt, 10).map { String(cString: $0) }
            let track = String(cString: sqlite3_column_text(stmt, 11))
            let score = sqlite3_column_double(stmt, 12)

            let tierRaw = String(cString: sqlite3_column_text(stmt, 13))
            let tier = Int(tierRaw) ?? 0

            let statusRaw = String(cString: sqlite3_column_text(stmt, 14))
            let status = PaperStatus(rawValue: statusRaw) ?? .pending
            let changedAtRaw = String(cString: sqlite3_column_text(stmt, 15))
            let changedAt = Self.parseSQLiteDate(changedAtRaw) ?? Date()
            let note = String(cString: sqlite3_column_text(stmt, 16))
            let abstractZh = String(cString: sqlite3_column_text(stmt, 17))

            var pubYear: Int? = nil
            if pubDate.count >= 4 {
                pubYear = Int(pubDate.prefix(4))
            }

            let paper = Paper(
                id: id,
                doi: doi,
                title: title,
                authors: authors,
                publicationDate: pubDate,
                publicationYear: pubYear,
                venue: venue,
                venueAbbr: venueAbbr,
                citedByCount: citedCount,
                abstract: abstract,
                landingPageUrl: landingPage,
                pdfUrl: pdfUrl,
                track: track,
                score: score,
                tier: tier,
                status: status,
                changedAt: changedAt,
                note: note,
                abstractZh: abstractZh
            )
            loadedPapers.append(paper)
        }

        self.papers = loadedPapers
        paperVersion += 1
    }

    func addOrUpdate(papers newPapers: [Paper]) -> (inserted: Int, updated: Int) {
        var inserted = 0
        var updated = 0

        for paper in newPapers {
            var existsStmt: OpaquePointer?
            let checkQuery = "SELECT 1 FROM papers WHERE id = ?"
            if sqlite3_prepare_v2(db, checkQuery, -1, &existsStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(existsStmt, 1, paper.id, -1, SQLITE_TRANSIENT)
                let exists = sqlite3_step(existsStmt) == SQLITE_ROW
                sqlite3_finalize(existsStmt)

                var authorsJson = ""
                if let authorsData = try? JSONEncoder().encode(paper.authors) {
                    authorsJson = String(data: authorsData, encoding: .utf8) ?? "[]"
                }

                if exists {
                    let updateSql = """
                    UPDATE papers SET
                        doi = ?, title = ?, authors = ?, publication_date = ?, venue = ?,
                        venue_abbr = ?, cited_by_count = ?, abstract = ?, landing_page_url = ?,
                        pdf_url = ?, track = ?, score = ?, tier = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """
                    var updateStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, updateSql, -1, &updateStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(updateStmt, 1, paper.doi, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(updateStmt, 2, paper.title, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(updateStmt, 3, authorsJson, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(updateStmt, 4, paper.publicationDate, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(updateStmt, 5, paper.venue, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(updateStmt, 6, paper.venueAbbr, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_int(updateStmt, 7, Int32(paper.citedByCount))
                        sqlite3_bind_text(updateStmt, 8, paper.abstract, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(updateStmt, 9, paper.landingPageUrl, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(updateStmt, 10, paper.pdfUrl, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(updateStmt, 11, paper.track, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_double(updateStmt, 12, paper.score)
                        sqlite3_bind_text(updateStmt, 13, String(paper.tier), -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(updateStmt, 14, paper.id, -1, SQLITE_TRANSIENT)

                        if sqlite3_step(updateStmt) == SQLITE_DONE {
                            updated += 1
                            replaceTopics(for: paper.id, track: paper.track)
                        }
                        sqlite3_finalize(updateStmt)
                    }
                } else {
                    let insertSql = """
                    INSERT INTO papers (
                        id, doi, title, authors, publication_date, venue, venue_abbr,
                        cited_by_count, abstract, landing_page_url, pdf_url, track, score, tier
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """
                    var insertStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(insertStmt, 1, paper.id, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 2, paper.doi, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 3, paper.title, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 4, authorsJson, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 5, paper.publicationDate, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 6, paper.venue, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 7, paper.venueAbbr, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_int(insertStmt, 8, Int32(paper.citedByCount))
                        sqlite3_bind_text(insertStmt, 9, paper.abstract, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 10, paper.landingPageUrl, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 11, paper.pdfUrl, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(insertStmt, 12, paper.track, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_double(insertStmt, 13, paper.score)
                        sqlite3_bind_text(insertStmt, 14, String(paper.tier), -1, SQLITE_TRANSIENT)

                        if sqlite3_step(insertStmt) == SQLITE_DONE {
                            inserted += 1
                            replaceTopics(for: paper.id, track: paper.track)

                            let stateSql = "INSERT OR IGNORE INTO paper_states (paper_id, status) VALUES (?, 'pending')"
                            var stateStmt: OpaquePointer?
                            if sqlite3_prepare_v2(db, stateSql, -1, &stateStmt, nil) == SQLITE_OK {
                                sqlite3_bind_text(stateStmt, 1, paper.id, -1, SQLITE_TRANSIENT)
                                sqlite3_step(stateStmt)
                                sqlite3_finalize(stateStmt)
                            }
                        }
                        sqlite3_finalize(insertStmt)
                    }
                }
            }
        }

        loadPapers()
        return (inserted, updated)
    }

    func refreshVenueMetadata() -> Int {
        let scorer = VenueScorer(
            config: ConfigManager.shared.effectiveConfig,
            venues: MetadataStore.shared.venues
        )
        let updateSql = """
        UPDATE papers
        SET venue_abbr = ?, score = ?, tier = ?, updated_at = datetime('now')
        WHERE id = ?
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, updateSql, -1, &stmt, nil) != SQLITE_OK {
            print("Failed to prepare venue metadata refresh")
            return 0
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
        var changed = 0

        for paper in papers {
            let venueAbbr = scorer.computeVenueAbbr(venue: paper.venue)
            let tier = scorer.getTier(venue: paper.venue)
            let score = scorer.calculateScore(venue: paper.venue, citations: paper.citedByCount)

            guard venueAbbr != paper.venueAbbr || tier != paper.tier || abs(score - paper.score) > 0.0001 else {
                continue
            }

            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, venueAbbr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, score)
            sqlite3_bind_text(stmt, 3, String(tier), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, paper.id, -1, SQLITE_TRANSIENT)

            if sqlite3_step(stmt) == SQLITE_DONE {
                changed += 1
            }
        }

        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        loadPapers()
        return changed
    }

    private func migratePaperTopicsIfNeeded() {
        guard tableIsEmpty("paper_topics") else { return }

        let query = "SELECT id, COALESCE(track, '') FROM papers WHERE COALESCE(track, '') != ''"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let paperId = String(cString: sqlite3_column_text(stmt, 0))
            let track = String(cString: sqlite3_column_text(stmt, 1))
            insertTopics(for: paperId, topics: Self.splitTopics(track))
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    private func tableIsEmpty(_ table: String) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM \(table) LIMIT 1", -1, &stmt, nil) == SQLITE_OK else {
            return true
        }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) != SQLITE_ROW
    }

    private func replaceTopics(for paperId: String, track: String) {
        let topics = Self.splitTopics(track)

        let deleteSql = "DELETE FROM paper_topics WHERE paper_id = ?"
        var deleteStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSql, -1, &deleteStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteStmt, 1, paperId, -1, SQLITE_TRANSIENT)
            sqlite3_step(deleteStmt)
            sqlite3_finalize(deleteStmt)
        }

        insertTopics(for: paperId, topics: topics)
    }

    private func insertTopics(for paperId: String, topics: [String]) {
        let insertSql = "INSERT OR IGNORE INTO paper_topics (paper_id, topic_name) VALUES (?, ?)"
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(insertStmt) }

        for topic in topics {
            sqlite3_reset(insertStmt)
            sqlite3_clear_bindings(insertStmt)
            sqlite3_bind_text(insertStmt, 1, paperId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insertStmt, 2, topic, -1, SQLITE_TRANSIENT)
            sqlite3_step(insertStmt)
        }
    }

    private static func splitTopics(_ track: String) -> [String] {
        track.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseSQLiteDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)
    }

    func setPaperStatus(id: String, status: PaperStatus) {
        let sql = """
        INSERT INTO paper_states (paper_id, status, changed_at)
        VALUES (?, ?, datetime('now'))
        ON CONFLICT(paper_id) DO UPDATE SET
            status = excluded.status,
            changed_at = datetime('now')
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, status.rawValue, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_DONE {
                if let idx = papers.firstIndex(where: { $0.id == id }) {
                    papers[idx].status = status
                    papers[idx].changedAt = Date()
                }
                paperVersion += 1
            }
            sqlite3_finalize(stmt)
        }
    }

    func setPaperNote(id: String, note: String) {
        let sql = """
        INSERT INTO paper_notes (paper_id, note, updated_at)
        VALUES (?, ?, datetime('now'))
        ON CONFLICT(paper_id) DO UPDATE SET
            note = excluded.note,
            updated_at = datetime('now')
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, note, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_DONE {
                if let idx = papers.firstIndex(where: { $0.id == id }) {
                    papers[idx].note = note
                }
                paperVersion += 1
            }
            sqlite3_finalize(stmt)
        }
    }

    func setPaperTranslation(id: String, abstractZh: String) {
        let sql = """
        INSERT INTO paper_translations (paper_id, abstract_zh, updated_at)
        VALUES (?, ?, datetime('now'))
        ON CONFLICT(paper_id) DO UPDATE SET
            abstract_zh = excluded.abstract_zh,
            updated_at = datetime('now')
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, abstractZh, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_DONE {
                if let idx = papers.firstIndex(where: { $0.id == id }) {
                    papers[idx].abstractZh = abstractZh
                }
                paperVersion += 1
            }
            sqlite3_finalize(stmt)
        }
    }

    func setPaperPdf(id: String, pdfUrl: String, pdfSource: String) {
        let sql = """
        INSERT INTO paper_pdfs (paper_id, pdf_url, pdf_source, resolved_at)
        VALUES (?, ?, ?, datetime('now'))
        ON CONFLICT(paper_id) DO UPDATE SET
            pdf_url = excluded.pdf_url,
            pdf_source = excluded.pdf_source,
            resolved_at = datetime('now')
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, pdfUrl, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, pdfSource, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_DONE {
                if let idx = papers.firstIndex(where: { $0.id == id }) {
                    papers[idx].pdfUrl = pdfUrl
                }
                paperVersion += 1
            }
            sqlite3_finalize(stmt)
        }
    }
}

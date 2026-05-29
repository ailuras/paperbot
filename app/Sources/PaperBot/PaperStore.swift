import Foundation
import SQLite3

@MainActor
class PaperStore: ObservableObject {
    @Published var papers: [Paper] = []
    
    static let shared = PaperStore()
    
    private var db: OpaquePointer?
    
    var dbURL: URL {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        
        // Target path as requested by user
        let targetDir = home.appendingPathComponent("Documents/06-文献/PaperBot")
        let targetDb = targetDir.appendingPathComponent("paperbot.db")
        
        // Ensure directory exists
        try? fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
        
        // Auto-migration check: If target DB does not exist, check legacy path ~/.paperbot/paperbot.db
        if !fileManager.fileExists(atPath: targetDb.path) {
            var legacyDir = home.appendingPathComponent(".paperbot")
            if let configDir = ConfigManager.shared.config?.data_dir {
                let expanded = (configDir as NSString).expandingTildeInPath
                legacyDir = URL(fileURLWithPath: expanded)
            }
            let legacyDb = legacyDir.appendingPathComponent("paperbot.db")
            
            if fileManager.fileExists(atPath: legacyDb.path) {
                print("Migrating database from \(legacyDb.path) to \(targetDb.path)...")
                do {
                    try fileManager.copyItem(at: legacyDb, to: targetDb)
                    print("Database migrated successfully!")
                } catch {
                    print("Failed to copy legacy database: \(error)")
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
            title_zh TEXT,
            abstract_zh TEXT,
            updated_at TEXT DEFAULT (datetime('now'))
        );
        
        CREATE TABLE IF NOT EXISTS paper_pdfs (
            paper_id TEXT PRIMARY KEY,
            pdf_url TEXT NOT NULL,
            pdf_source TEXT,
            resolved_at TEXT DEFAULT (datetime('now'))
        );
        """
        
        var errorMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, schema, nil, nil, &errorMsg) != SQLITE_OK {
            let error = errorMsg.map { String(cString: $0) } ?? "unknown error"
            print("Error creating tables: \(error)")
            sqlite3_free(errorMsg)
        }
    }
    
    func loadPapers() {
        let query = """
        SELECT p.id, p.doi, p.title, p.authors, p.publication_date, p.venue, p.venue_abbr,
               p.cited_by_count, p.abstract, p.landing_page_url, COALESCE(f.pdf_url, p.pdf_url) as pdf_url,
               p.track, p.score, p.tier, COALESCE(ps.status, 'pending') as status,
               COALESCE(pn.note, '') as note, COALESCE(pt.title_zh, '') as title_zh, COALESCE(pt.abstract_zh, '') as abstract_zh
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
            
            let status = String(cString: sqlite3_column_text(stmt, 14))
            let note = String(cString: sqlite3_column_text(stmt, 15))
            let titleZh = String(cString: sqlite3_column_text(stmt, 16))
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
                note: note,
                titleZh: titleZh,
                abstractZh: abstractZh
            )
            loadedPapers.append(paper)
        }
        
        self.papers = loadedPapers
    }
    
    func addOrUpdate(papers newPapers: [Paper]) -> (inserted: Int, updated: Int) {
        var inserted = 0
        var updated = 0
        
        for paper in newPapers {
            var existsStmt: OpaquePointer?
            let checkQuery = "SELECT 1 FROM papers WHERE id = ?"
            if sqlite3_prepare_v2(db, checkQuery, -1, &existsStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(existsStmt, 1, paper.id, -1, nil)
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
                        cited_by_count = ?, abstract = ?, landing_page_url = ?, pdf_url = ?,
                        track = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """
                    var updateStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, updateSql, -1, &updateStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(updateStmt, 1, paper.doi, -1, nil)
                        sqlite3_bind_text(updateStmt, 2, paper.title, -1, nil)
                        sqlite3_bind_text(updateStmt, 3, authorsJson, -1, nil)
                        sqlite3_bind_text(updateStmt, 4, paper.publicationDate, -1, nil)
                        sqlite3_bind_text(updateStmt, 5, paper.venue, -1, nil)
                        sqlite3_bind_int(updateStmt, 6, Int32(paper.citedByCount))
                        sqlite3_bind_text(updateStmt, 7, paper.abstract, -1, nil)
                        sqlite3_bind_text(updateStmt, 8, paper.landingPageUrl, -1, nil)
                        sqlite3_bind_text(updateStmt, 9, paper.pdfUrl, -1, nil)
                        sqlite3_bind_text(updateStmt, 10, paper.track, -1, nil)
                        sqlite3_bind_text(updateStmt, 11, paper.id, -1, nil)
                        
                        if sqlite3_step(updateStmt) == SQLITE_DONE {
                            updated += 1
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
                        sqlite3_bind_text(insertStmt, 1, paper.id, -1, nil)
                        sqlite3_bind_text(insertStmt, 2, paper.doi, -1, nil)
                        sqlite3_bind_text(insertStmt, 3, paper.title, -1, nil)
                        sqlite3_bind_text(insertStmt, 4, authorsJson, -1, nil)
                        sqlite3_bind_text(insertStmt, 5, paper.publicationDate, -1, nil)
                        sqlite3_bind_text(insertStmt, 6, paper.venue, -1, nil)
                        sqlite3_bind_text(insertStmt, 7, paper.venueAbbr, -1, nil)
                        sqlite3_bind_int(insertStmt, 8, Int32(paper.citedByCount))
                        sqlite3_bind_text(insertStmt, 9, paper.abstract, -1, nil)
                        sqlite3_bind_text(insertStmt, 10, paper.landingPageUrl, -1, nil)
                        sqlite3_bind_text(insertStmt, 11, paper.pdfUrl, -1, nil)
                        sqlite3_bind_text(insertStmt, 12, paper.track, -1, nil)
                        sqlite3_bind_double(insertStmt, 13, paper.score)
                        sqlite3_bind_text(insertStmt, 14, String(paper.tier), -1, nil)
                        
                        if sqlite3_step(insertStmt) == SQLITE_DONE {
                            inserted += 1
                            
                            // Auto-mark new papers as pending
                            let stateSql = "INSERT OR IGNORE INTO paper_states (paper_id, status) VALUES (?, 'pending')"
                            var stateStmt: OpaquePointer?
                            if sqlite3_prepare_v2(db, stateSql, -1, &stateStmt, nil) == SQLITE_OK {
                                sqlite3_bind_text(stateStmt, 1, paper.id, -1, nil)
                                sqlite3_step(stateStmt)
                                sqlite3_finalize(stateStmt)
                            }
                        }
                        sqlite3_finalize(insertStmt)
                    }
                }
            }
        }
        
        // Reload into memory
        loadPapers()
        return (inserted, updated)
    }
    
    func setPaperStatus(id: String, status: String) {
        let sql = """
        INSERT INTO paper_states (paper_id, status, changed_at)
        VALUES (?, ?, datetime('now'))
        ON CONFLICT(paper_id) DO UPDATE SET
            status = excluded.status,
            changed_at = datetime('now')
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, nil)
            sqlite3_bind_text(stmt, 2, status, -1, nil)
            if sqlite3_step(stmt) == SQLITE_DONE {
                // Update memory
                if let idx = papers.firstIndex(where: { $0.id == id }) {
                    papers[idx].status = status
                    papers[idx].changedAt = Date()
                }
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
            sqlite3_bind_text(stmt, 1, id, -1, nil)
            sqlite3_bind_text(stmt, 2, note, -1, nil)
            if sqlite3_step(stmt) == SQLITE_DONE {
                // Update memory
                if let idx = papers.firstIndex(where: { $0.id == id }) {
                    papers[idx].note = note
                }
            }
            sqlite3_finalize(stmt)
        }
    }
    
    func setPaperTranslation(id: String, titleZh: String, abstractZh: String) {
        let sql = """
        INSERT INTO paper_translations (paper_id, title_zh, abstract_zh, updated_at)
        VALUES (?, ?, ?, datetime('now'))
        ON CONFLICT(paper_id) DO UPDATE SET
            title_zh = excluded.title_zh,
            abstract_zh = excluded.abstract_zh,
            updated_at = datetime('now')
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, nil)
            sqlite3_bind_text(stmt, 2, titleZh, -1, nil)
            sqlite3_bind_text(stmt, 3, abstractZh, -1, nil)
            if sqlite3_step(stmt) == SQLITE_DONE {
                // Update memory
                if let idx = papers.firstIndex(where: { $0.id == id }) {
                    papers[idx].titleZh = titleZh
                    papers[idx].abstractZh = abstractZh
                }
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
            sqlite3_bind_text(stmt, 1, id, -1, nil)
            sqlite3_bind_text(stmt, 2, pdfUrl, -1, nil)
            sqlite3_bind_text(stmt, 3, pdfSource, -1, nil)
            if sqlite3_step(stmt) == SQLITE_DONE {
                // Update memory
                if let idx = papers.firstIndex(where: { $0.id == id }) {
                    papers[idx].pdfUrl = pdfUrl
                }
            }
            sqlite3_finalize(stmt)
        }
    }
}

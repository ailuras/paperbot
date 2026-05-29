import Foundation
import SQLite3

class SQLiteMigrator {
    static func migrateIfNeeded(dbPath: URL, jsonPath: URL) {
        let fileManager = FileManager.default
        // If papers.json already exists, don't overwrite it
        if fileManager.fileExists(atPath: jsonPath.path) {
            return
        }
        
        // If paperbot.db doesn't exist, nothing to migrate
        if !fileManager.fileExists(atPath: dbPath.path) {
            print("No legacy database found at \(dbPath.path), skipping migration.")
            return
        }
        
        print("Legacy database found at \(dbPath.path). Starting migration to JSON...")
        
        var db: OpaquePointer?
        if sqlite3_open(dbPath.path, &db) != SQLITE_OK {
            print("Failed to open legacy SQLite database for migration.")
            return
        }
        defer {
            sqlite3_close(db)
        }
        
        let query = """
        SELECT p.id, p.doi, p.title, p.authors, p.publication_date, p.venue, p.venue_abbr,
               p.cited_by_count, p.abstract, p.landing_page_url, COALESCE(f.pdf_url, p.pdf_url) as pdfUrl,
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
            let errmsg = String(cString: sqlite3_errmsg(db))
            print("Prepare statement failed: \(errmsg)")
            return
        }
        defer {
            sqlite3_finalize(stmt)
        }
        
        var migratedPapers: [Paper] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let doi = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let title = String(cString: sqlite3_column_text(stmt, 2))
            
            // Authors is stored as JSON string in SQLite
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
            
            // Tier in DB might be stored as string "1", "2"
            let tierRaw = String(cString: sqlite3_column_text(stmt, 13))
            let tier = Int(tierRaw) ?? 0
            
            let status = String(cString: sqlite3_column_text(stmt, 14))
            let note = String(cString: sqlite3_column_text(stmt, 15))
            let titleZh = String(cString: sqlite3_column_text(stmt, 16))
            let abstractZh = String(cString: sqlite3_column_text(stmt, 17))
            
            // Extract publication year from pubDate
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
            migratedPapers.append(paper)
        }
        
        // Write migrated papers to papers.json
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(migratedPapers)
            try data.write(to: jsonPath, options: .atomic)
            print("Successfully migrated \(migratedPapers.count) papers to JSON!")
        } catch {
            print("Failed to save migrated JSON papers: \(error)")
        }
    }
}

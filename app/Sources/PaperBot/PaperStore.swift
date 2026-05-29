import Foundation

@MainActor
class PaperStore: ObservableObject {
    @Published var papers: [Paper] = []
    
    static let shared = PaperStore()
    
    private var dataURL: URL {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        
        // Use data_dir from config if available, fallback to ~/.paperbot
        var dirURL = home.appendingPathComponent(".paperbot")
        if let configDir = ConfigManager.shared.config?.data_dir {
            let expanded = (configDir as NSString).expandingTildeInPath
            dirURL = URL(fileURLWithPath: expanded)
        }
        
        // Ensure directory exists
        try? fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        return dirURL.appendingPathComponent("papers.json")
    }
    
    private init() {
        loadPapers()
    }
    
    func loadPapers() {
        let fileManager = FileManager.default
        let url = dataURL
        
        // SQLite DB migration check
        var dirURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".paperbot")
        if let configDir = ConfigManager.shared.config?.data_dir {
            let expanded = (configDir as NSString).expandingTildeInPath
            dirURL = URL(fileURLWithPath: expanded)
        }
        let dbURL = dirURL.appendingPathComponent("paperbot.db")
        SQLiteMigrator.migrateIfNeeded(dbPath: dbURL, jsonPath: url)
        
        if fileManager.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                self.papers = try decoder.decode([Paper].self, from: data)
                print("Loaded \(papers.count) papers from \(url.path)")
            } catch {
                print("Error loading papers: \(error)")
            }
        } else {
            self.papers = []
        }
    }
    
    func savePapers() {
        let url = dataURL
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(papers)
            try data.write(to: url, options: .atomic)
            print("Saved \(papers.count) papers to \(url.path)")
        } catch {
            print("Error saving papers: \(error)")
        }
    }
    
    func addOrUpdate(papers newPapers: [Paper]) -> (inserted: Int, updated: Int) {
        var inserted = 0
        var updated = 0
        
        var dict = Dictionary(uniqueKeysWithValues: papers.map { ($0.id, $0) })
        
        for paper in newPapers {
            if let existing = dict[paper.id] {
                // Update fields
                existing.doi = paper.doi
                existing.title = paper.title
                existing.authors = paper.authors
                existing.publicationDate = paper.publicationDate
                existing.publicationYear = paper.publicationYear
                existing.venue = paper.venue
                existing.venueAbbr = paper.venueAbbr
                existing.citedByCount = paper.citedByCount
                existing.abstract = paper.abstract
                existing.landingPageUrl = paper.landingPageUrl
                if paper.pdfUrl != nil {
                    existing.pdfUrl = paper.pdfUrl
                }
                existing.track = paper.track
                existing.score = paper.score
                existing.tier = paper.tier
                existing.changedAt = Date()
                updated += 1
            } else {
                dict[paper.id] = paper
                inserted += 1
            }
        }
        
        self.papers = Array(dict.values)
        savePapers()
        return (inserted, updated)
    }
    
    func setPaperStatus(id: String, status: String) {
        if let idx = papers.firstIndex(where: { $0.id == id }) {
            papers[idx].status = status
            papers[idx].changedAt = Date()
            savePapers()
        }
    }
    
    func setPaperNote(id: String, note: String) {
        if let idx = papers.firstIndex(where: { $0.id == id }) {
            papers[idx].note = note
            savePapers()
        }
    }
}

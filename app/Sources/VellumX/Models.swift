import Foundation

final class Paper: Codable, Identifiable {
    var id: String // OpenAlex ID
    var doi: String?
    var title: String
    var authors: [String]
    var publicationDate: String
    var publicationYear: Int?
    var venue: String
    var venueAbbr: String
    var citedByCount: Int
    var abstract: String
    var landingPageUrl: String
    var pdfUrl: String?
    var track: String
    var score: Double
    var tier: Int
    var status: String // "pending", "recommended", "read", "starred", "skip"
    var changedAt: Date
    var note: String
    var titleZh: String
    var abstractZh: String
    
    init(id: String, doi: String? = nil, title: String, authors: [String] = [], publicationDate: String = "", publicationYear: Int? = nil, venue: String = "", venueAbbr: String = "", citedByCount: Int = 0, abstract: String = "", landingPageUrl: String = "", pdfUrl: String? = nil, track: String = "", score: Double = 0.0, tier: Int = 0, status: String = "pending", changedAt: Date = Date(), note: String = "", titleZh: String = "", abstractZh: String = "") {
        self.id = id
        self.doi = doi
        self.title = title
        self.authors = authors
        self.publicationDate = publicationDate
        self.publicationYear = publicationYear
        self.venue = venue
        self.venueAbbr = venueAbbr
        self.citedByCount = citedByCount
        self.abstract = abstract
        self.landingPageUrl = landingPageUrl
        self.pdfUrl = pdfUrl
        self.track = track
        self.score = score
        self.tier = tier
        self.status = status
        self.changedAt = changedAt
        self.note = note
        self.titleZh = titleZh
        self.abstractZh = abstractZh
    }
}

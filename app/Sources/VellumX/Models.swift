import Foundation
import SwiftUI

enum PaperStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case recommended = "recommended"
    case read = "read"
    case starred = "starred"
    case skip = "skip"

    var displayName: String {
        switch self {
        case .pending:     return "Pending"
        case .recommended: return "Recommended"
        case .read:        return "Read"
        case .starred:     return "Starred"
        case .skip:        return "Skip"
        }
    }

    var iconName: String {
        switch self {
        case .pending:     return "clock"
        case .recommended: return "sparkles"
        case .read:        return "checkmark.circle"
        case .starred:     return "star.fill"
        case .skip:        return "eye.slash"
        }
    }

    var iconColor: Color {
        switch self {
        case .pending:     return .blue
        case .recommended: return .orange
        case .read:        return .green
        case .starred:     return .yellow
        case .skip:        return .secondary
        }
    }
}

/// Lightweight in-memory paper DTO used by the UI layer.
/// Persistence is handled by `PersistedPaper` via SwiftData.
final class Paper: Identifiable {
    var id: String
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
    var status: PaperStatus
    var changedAt: Date
    var note: String
    var titleZh: String
    var abstractZh: String

    init(
        id: String, doi: String? = nil, title: String,
        authors: [String] = [], publicationDate: String = "",
        publicationYear: Int? = nil, venue: String = "",
        venueAbbr: String = "", citedByCount: Int = 0,
        abstract: String = "", landingPageUrl: String = "",
        pdfUrl: String? = nil, track: String = "",
        score: Double = 0.0, tier: Int = 0,
        status: PaperStatus = .pending, changedAt: Date = Date(),
        note: String = "", titleZh: String = "", abstractZh: String = ""
    ) {
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

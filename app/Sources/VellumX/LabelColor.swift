import SwiftUI

/// A small palette of named colors used for sidebar filter labels. Stored by
/// name (in the metadata tables, e.g. `metadata_topics.color`) so persistence
/// stays human-readable and dependency-free.
enum LabelColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .gray: return .gray
        }
    }

    /// Display label (capitalized name).
    var title: String { rawValue.capitalized }

    static func color(named name: String?) -> Color? {
        guard let name, let c = LabelColor(rawValue: name) else { return nil }
        return c.color
    }
}

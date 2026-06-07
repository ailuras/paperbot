import SwiftUI

/// Rounded tinted folder badge shown next to each collection in the sidebar.
/// Always uses the folder glyph; color reflects the collection's label color.
struct CollectionBadge: View {
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(color.opacity(0.14))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "folder")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(color)
            )
    }
}

extension PaperCollection {
    var resolvedColor: Color { LabelColor.color(named: color) ?? .accentColor }
}

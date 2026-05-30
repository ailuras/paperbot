import SwiftUI

/// A multi-select sidebar filter row (Topics / Fields / Tier). Shows a colored
/// dot icon (the color lives on the icon, not the text), the label, and a
/// checkmark when selected. Tapping toggles selection; right-click sets the
/// color, persisted in AppSettings.labelColors under `colorKey`.
struct FilterRow: View {
    let title: String
    let colorKey: String
    let defaultColor: LabelColor
    let isSelected: Bool
    let onToggle: () -> Void

    @ObservedObject private var settings = AppSettings.shared

    private var color: Color {
        LabelColor.color(named: settings.labelColors[colorKey]) ?? defaultColor.color
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu("Color") {
                ForEach(LabelColor.allCases) { c in
                    Button(c.title) { settings.labelColors[colorKey] = c.rawValue }
                }
                Divider()
                Button("Default") { settings.labelColors[colorKey] = nil }
            }
        }
    }
}

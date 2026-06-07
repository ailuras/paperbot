import SwiftUI

// MARK: - Badge

/// Rounded tinted icon badge for a collection, mirroring the TopicBadge style.
struct CollectionBadge: View {
    let color: Color
    let icon: String
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(color.opacity(0.14))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(color)
            )
    }
}

extension PaperCollection {
    var resolvedColor: Color { LabelColor.color(named: color) ?? .accentColor }
    var displayIcon: String { icon ?? "folder" }
}

// MARK: - Edit target

enum CollectionEditTarget: Identifiable {
    case new(parentId: String?)
    case edit(PaperCollection)

    var id: String {
        switch self {
        case .new(let parentId): return "new-\(parentId ?? "root")"
        case .edit(let c): return c.id
        }
    }
}

// MARK: - Editor sheet

/// Modal editor for one collection: name, notes, color, and sidebar glyph.
/// Commits to `PaperStore` on Save.
struct CollectionEditor: View {
    let target: CollectionEditTarget

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var notes: String
    @State private var color: String?
    @State private var icon: String?

    init(target: CollectionEditTarget) {
        self.target = target
        switch target {
        case .new:
            _name  = State(initialValue: "")
            _notes = State(initialValue: "")
            _color = State(initialValue: nil)
            _icon  = State(initialValue: nil)
        case .edit(let c):
            _name  = State(initialValue: c.name)
            _notes = State(initialValue: c.notes ?? "")
            _color = State(initialValue: c.color)
            _icon  = State(initialValue: c.icon)
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { !trimmedName.isEmpty }
    private var resolvedColor: Color { LabelColor.color(named: color) ?? .accentColor }
    private var displayIcon: String { icon ?? "folder" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New Collection" : "Edit Collection")
                .font(.system(size: 15, weight: .semibold))

            preview
            Divider()
            fields
            colorPicker
            iconPicker
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 440)
    }

    // MARK: - Subviews

    private var preview: some View {
        HStack(spacing: 10) {
            CollectionBadge(color: resolvedColor, icon: displayIcon, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(trimmedName.isEmpty ? "Untitled" : trimmedName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(trimmedName.isEmpty ? .secondary : .primary)
                let notesPreview = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !notesPreview.isEmpty {
                    Text(notesPreview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledField("Name") {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            }
            labeledField("Notes") {
                TextField("Optional description", text: $notes).textFieldStyle(.roundedBorder)
            }
        }
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.75))
            content()
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Color".uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.75))
            HStack(spacing: 8) {
                ForEach(LabelColor.allCases) { c in
                    Circle()
                        .fill(c.color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle().stroke(Color.primary.opacity(0.85), lineWidth: color == c.rawValue ? 2 : 0)
                        )
                        .overlay(
                            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                        .contentShape(Circle())
                        .onTapGesture { color = c.rawValue }
                }
            }
        }
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Icon".uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.75))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 9), spacing: 6) {
                ForEach(SidebarGlyph.choices, id: \.symbol) { choice in
                    Button {
                        icon = choice.symbol
                    } label: {
                        Image(systemName: choice.symbol)
                            .font(.system(size: 13))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(icon == choice.symbol ? resolvedColor : .secondary)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(icon == choice.symbol ? resolvedColor.opacity(0.16) : Color.secondary.opacity(0.08))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(choice.label)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
        }
    }

    // MARK: - Actions

    private func save() {
        guard isValid else { return }
        let finalNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        switch target {
        case .new(let parentId):
            PaperStore.shared.createCollection(
                name: trimmedName,
                color: color,
                icon: icon,
                parentId: parentId,
                notes: finalNotes.isEmpty ? nil : finalNotes
            )
        case .edit(let c):
            PaperStore.shared.renameCollection(id: c.id, to: trimmedName)
            PaperStore.shared.setCollectionColor(id: c.id, color: color)
            PaperStore.shared.setCollectionIcon(id: c.id, icon: icon)
            PaperStore.shared.setCollectionNotes(id: c.id, notes: finalNotes.isEmpty ? nil : finalNotes)
        }
        dismiss()
    }
}

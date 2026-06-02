import SwiftUI

struct SidebarView: View {
    @Binding var selectedItem: SidebarItem?
    @Binding var selectedCollectionId: String?
    @Binding var selectedTopic: String?
    @Binding var includedTags: Set<String>
    @Binding var excludedTags: Set<String>
    let tags: [String]
    let collections: [PaperCollection]
    var metadata: MetadataStore
    let statusMessage: String
    let papers: [Paper]

    @State private var expandedCollections: Set<String> = []
    @State private var nameEdit: CollectionNameEdit?
    @State private var nameText: String = ""
    @State private var deleteTarget: PaperCollection?

    /// Pending name-input dialog (rename / new subfolder / new root).
    private enum CollectionNameEdit: Identifiable {
        case rename(PaperCollection)
        case newSubfolder(PaperCollection)
        case newRoot
        var id: String {
            switch self {
            case .rename(let c):      return "rename-\(c.id)"
            case .newSubfolder(let c): return "sub-\(c.id)"
            case .newRoot:            return "root"
            }
        }
    }

    /// Collections grouped by their parent id (roots are resolved separately).
    private var childrenByParent: [String: [PaperCollection]] {
        Dictionary(grouping: collections) { $0.parentId ?? "" }
    }

    /// Top-level folders: no parent, or a parent that no longer exists (orphans).
    private var rootCollections: [PaperCollection] {
        let ids = Set(collections.map(\.id))
        return collections.filter { c in
            guard let pid = c.parentId else { return true }
            return !ids.contains(pid)
        }
    }

    var body: some View {
        List(selection: $selectedItem) {
            Section("Library") {
                ForEach([SidebarItem.recommended, .pending, .starred, .read, .skipped, .all], id: \.self) { item in
                    NavigationLink(value: item) {
                        HStack {
                            Label {
                                Text(item.displayName)
                            } icon: {
                                Image(systemName: item.iconName)
                                    .foregroundStyle(item.iconColor)
                            }
                            Spacer()
                            let count = paperCount(for: item)
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }
            }

            if !metadata.topics.isEmpty {
                Section("Topics") {
                    ForEach(metadata.topics.map(\.name), id: \.self) { name in
                        FilterRow(title: name, colorKey: "topic:\(name)",
                                  defaultColor: .purple,
                                  isSelected: selectedTopic == name) {
                            selectedTopic = (selectedTopic == name) ? nil : name
                        }
                    }
                }
            }

            if !tags.isEmpty {
                Section("Tags") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], alignment: .leading, spacing: 8) {
                        TagFilterChip(
                            title: "All",
                            state: includedTags.isEmpty && excludedTags.isEmpty ? .include : .neutral
                        ) {
                            includedTags.removeAll()
                            excludedTags.removeAll()
                        }
                        ForEach(tags, id: \.self) { tag in
                            TagFilterChip(title: "#\(tag)", state: tagState(tag)) {
                                cycleTag(tag)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }

            Section {
                ForEach(rootCollections) { collection in
                    CollectionTreeRow(
                        collection: collection,
                        depth: 0,
                        childrenByParent: childrenByParent,
                        expanded: $expandedCollections,
                        selectedCollectionId: selectedCollectionId,
                        onSelect: selectCollection,
                        onRename: { startRename($0) },
                        onAddSubfolder: { startNewSubfolder($0) },
                        onDelete: { deleteTarget = $0 }
                    )
                }
            } header: {
                HStack {
                    Text("Collections")
                    Spacer()
                    Button {
                        nameText = ""
                        nameEdit = .newRoot
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 20, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("New collection")
                    .padding(.trailing, 8)
                }
            }
        }
        .listStyle(.sidebar)
        .alert(nameEditTitle, isPresented: Binding(
            get: { nameEdit != nil },
            set: { if !$0 { nameEdit = nil } }
        )) {
            TextField("Name", text: $nameText)
            Button("Save", action: commitNameEdit)
            Button("Cancel", role: .cancel) { nameText = "" }
        }
        .alert("Delete “\(deleteTarget?.name ?? "")”?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        ), presenting: deleteTarget) { target in
            Button("Delete", role: .destructive) { confirmDelete(target) }
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("This also deletes its subfolders. Your papers stay in the library.")
        }
        .safeAreaInset(edge: .bottom) {
            if !statusMessage.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }

    private func paperCount(for item: SidebarItem) -> Int {
        switch item {
        case .all: return papers.count
        case .recommended: return papers.filter { $0.isRecommended }.count
        case .pending: return papers.filter { $0.status == .pending }.count
        case .starred: return papers.filter { $0.status == .starred }.count
        case .read: return papers.filter { $0.status == .read }.count
        case .skipped: return papers.filter { $0.status == .skip }.count
        }
    }

    private func tagState(_ tag: String) -> TagFilterState {
        if includedTags.contains(tag) { return .include }
        if excludedTags.contains(tag) { return .exclude }
        return .neutral
    }

    private func cycleTag(_ tag: String) {
        if includedTags.remove(tag) != nil {
            excludedTags.insert(tag)
        } else if excludedTags.remove(tag) != nil {
            return
        } else {
            includedTags.insert(tag)
        }
    }

    // MARK: - Collections actions

    private func selectCollection(_ collection: PaperCollection) {
        selectedCollectionId = (selectedCollectionId == collection.id) ? nil : collection.id
        if selectedCollectionId != nil { selectedItem = nil }
    }

    private func startRename(_ collection: PaperCollection) {
        nameText = collection.name
        nameEdit = .rename(collection)
    }

    private func startNewSubfolder(_ parent: PaperCollection) {
        nameText = ""
        nameEdit = .newSubfolder(parent)
    }

    private var nameEditTitle: String {
        switch nameEdit {
        case .rename:       return "Rename Collection"
        case .newSubfolder: return "New Subfolder"
        case .newRoot, .none: return "New Collection"
        }
    }

    private func commitNameEdit() {
        let text = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { nameText = "" }
        guard !text.isEmpty else { return }
        switch nameEdit {
        case .rename(let c):
            PaperStore.shared.renameCollection(id: c.id, to: text)
        case .newSubfolder(let parent):
            PaperStore.shared.createCollection(name: text, parentId: parent.id)
            expandedCollections.insert(parent.id)
        case .newRoot, .none:
            PaperStore.shared.createCollection(name: text)
        }
    }

    private func confirmDelete(_ target: PaperCollection) {
        // Clear the selection if it points anywhere inside the doomed subtree.
        let subtree = PaperStore.shared.collectionSubtreeIds(target.id)
        if let sel = selectedCollectionId, subtree.contains(sel) {
            selectedCollectionId = nil
        }
        PaperStore.shared.deleteCollection(id: target.id)
    }
}

enum TagFilterState {
    case neutral
    case include
    case exclude
}

private struct TagFilterChip: View {
    let title: String
    let state: TagFilterState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .strikethrough(state == .exclude)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(backgroundColor)
                .foregroundStyle(foregroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(borderColor, lineWidth: state == .neutral ? 0.5 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch state {
        case .neutral: return Color.secondary.opacity(0.16)
        case .include: return Color.accentColor.opacity(0.20)
        case .exclude: return Color.red.opacity(0.16)
        }
    }

    private var foregroundColor: Color {
        switch state {
        case .neutral: return .primary.opacity(0.82)
        case .include: return .accentColor
        case .exclude: return .red.opacity(0.85)
        }
    }

    private var borderColor: Color {
        switch state {
        case .neutral: return Color.gray.opacity(0.18)
        case .include: return Color.accentColor.opacity(0.45)
        case .exclude: return Color.red.opacity(0.35)
        }
    }
}

/// A curated palette of folder glyphs offered in the right-click "Icon" submenu.
private enum CollectionIcon {
    static let choices: [(symbol: String, label: String)] = [
        ("folder", "Folder"), ("tray.full", "Tray"), ("book", "Book"),
        ("graduationcap", "Academic"), ("doc.text", "Document"), ("bookmark", "Bookmark"),
        ("star", "Star"), ("flag", "Flag"), ("tag", "Tag"),
        ("lightbulb", "Idea"), ("paperclip", "Clip"), ("archivebox", "Archive"),
    ]
}

/// One collection row plus its (lazily expanded) descendants. Recurses into
/// itself for children, so the whole subtree renders as flat sidebar rows with
/// growing indentation — a restrained, Finder-like look.
private struct CollectionTreeRow: View {
    let collection: PaperCollection
    let depth: Int
    let childrenByParent: [String: [PaperCollection]]
    @Binding var expanded: Set<String>
    let selectedCollectionId: String?
    let onSelect: (PaperCollection) -> Void
    let onRename: (PaperCollection) -> Void
    let onAddSubfolder: (PaperCollection) -> Void
    let onDelete: (PaperCollection) -> Void
    @State private var isContextMenuPresented = false

    private var children: [PaperCollection] { childrenByParent[collection.id] ?? [] }
    private var hasChildren: Bool { !children.isEmpty }
    private var isExpanded: Bool { expanded.contains(collection.id) }
    private var isSelected: Bool { selectedCollectionId == collection.id }
    private var showsSelectionFrame: Bool { isSelected && !isContextMenuPresented }

    var body: some View {
        row
        if hasChildren && isExpanded {
            ForEach(children) { child in
                CollectionTreeRow(
                    collection: child,
                    depth: depth + 1,
                    childrenByParent: childrenByParent,
                    expanded: $expanded,
                    selectedCollectionId: selectedCollectionId,
                    onSelect: onSelect,
                    onRename: onRename,
                    onAddSubfolder: onAddSubfolder,
                    onDelete: onDelete
                )
            }
        }
    }

    private var row: some View {
        HStack(spacing: 5) {
            disclosure
            Button { onSelect(collection) } label: {
                collectionLabel
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 14)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background {
            if showsSelectionFrame {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.07))
            }
        }
        .overlay {
            if showsSelectionFrame {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.95), lineWidth: 1)
            }
        }
        .padding(.trailing, 8)
        .contextMenu { contextMenu }
    }

    private var collectionLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: collection.icon ?? "folder")
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 18)
            Text(collection.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .contentShape(Rectangle())
    }

    private var disclosure: some View {
        Group {
            if hasChildren {
                Button {
                    if isExpanded { expanded.remove(collection.id) }
                    else { expanded.insert(collection.id) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
            }
        }
        .frame(width: 10)
    }

    @ViewBuilder private var contextMenu: some View {
        Button("Rename…") { onRename(collection) }
            .onAppear { isContextMenuPresented = true }
            .onDisappear { isContextMenuPresented = false }
        Button("New Subfolder…") { onAddSubfolder(collection) }
        Menu("Icon") {
            ForEach(CollectionIcon.choices, id: \.symbol) { choice in
                Button {
                    PaperStore.shared.setCollectionIcon(id: collection.id, icon: choice.symbol)
                } label: {
                    Label(choice.label, systemImage: choice.symbol)
                }
            }
            Divider()
            Button("Default") { PaperStore.shared.setCollectionIcon(id: collection.id, icon: nil) }
        }
        Menu("Color") {
            ForEach(LabelColor.allCases) { c in
                Button(c.title) { PaperStore.shared.setCollectionColor(id: collection.id, color: c.rawValue) }
            }
            Divider()
            Button("Default") { PaperStore.shared.setCollectionColor(id: collection.id, color: nil) }
        }
        Divider()
        Button("Delete", role: .destructive) { onDelete(collection) }
    }

    private var iconColor: Color {
        if let colorName = collection.color, let labelColor = LabelColor(rawValue: colorName) {
            return labelColor.color
        }
        return .accentColor
    }
}

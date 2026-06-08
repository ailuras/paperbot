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
    let papers: [Paper]

    @State private var expandedCollections: Set<String> = []
    @State private var topicSheet: TopicEditTarget?
    @State private var editingCollectionId: String? = nil
    @State private var editingCollectionName: String = ""
    @State private var archivedExpanded = false

    private var activeTopics: [TrackPref] { metadata.topics.filter { !$0.archived } }
    private var archivedTopics: [TrackPref] { metadata.topics.filter { $0.archived } }

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
                ForEach([SidebarItem.recommended, .pending, .read, .starred, .skipped, .all], id: \.self) { item in
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

            Section {
                ForEach(activeTopics) { topic in
                    TopicSidebarRow(
                        topic: topic,
                        isSelected: selectedTopic == topic.name,
                        isArchived: false,
                        onSelect: { toggleTopic(topic.name) },
                        onEdit: { topicSheet = .edit(topic) },
                        onArchive: { archiveTopic(topic) },
                        onRestore: {},
                        onDelete: { confirmDeleteTopic(topic) }
                    )
                    .listRowBackground(topicRowBackground(topic))
                }

                if !archivedTopics.isEmpty {
                    archivedDisclosure
                    if archivedExpanded {
                        ForEach(archivedTopics) { topic in
                            TopicSidebarRow(
                                topic: topic,
                                isSelected: false,
                                isArchived: true,
                                onSelect: {},
                                onEdit: { topicSheet = .edit(topic) },
                                onArchive: {},
                                onRestore: { restoreTopic(topic) },
                                onDelete: { confirmDeleteTopic(topic) }
                            )
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Topics")
                    Spacer()
                    Button {
                        topicSheet = .new
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 20, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("New topic")
                    .padding(.trailing, 8)
                }
            }

            if !tags.isEmpty {
                Section("Tags") {
                    FlowLayout(spacing: 6) {
                        AllTagsChip(isActive: includedTags.isEmpty && excludedTags.isEmpty) {
                            includedTags.removeAll()
                            excludedTags.removeAll()
                        }
                        ForEach(tags, id: \.self) { tag in
                            TagFilterChip(tag: tag, state: tagState(tag)) {
                                cycleTag(tag)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                        papers: papers,
                        editingCollectionId: $editingCollectionId,
                        editingCollectionName: $editingCollectionName,
                        onSelect: selectCollection,
                        onCommitRename: commitCollectionRename,
                        onAddSubfolder: { startNewSubfolder($0) },
                        onDelete: { confirmDelete($0) }
                    )
                }
            } header: {
                HStack {
                    Text("Collections")
                    Spacer()
                    Button {
                        startNewRoot()
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
        .sheet(item: $topicSheet) { sheet in
            TopicEditor(existing: sheet.existing)
        }
    }

    /// Collapsible header for the archived-topics group at the bottom of Topics.
    private var archivedDisclosure: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { archivedExpanded.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(archivedExpanded ? 90 : 0))
                Text("Archived")
                Text("\(archivedTopics.count)")
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Topics actions

    /// Selection fill for a topic row, drawn at the row-cell level so it matches
    /// the native sidebar selection width. Inset slightly to leave the same side
    /// margins as the system highlight.
    @ViewBuilder
    private func topicRowBackground(_ topic: TrackPref) -> some View {
        if selectedTopic == topic.name {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.25))
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
        } else {
            Color.clear
        }
    }

    private func toggleTopic(_ name: String) {
        selectedTopic = (selectedTopic == name) ? nil : name
    }

    private func archiveTopic(_ topic: TrackPref) {
        if selectedTopic == topic.name { selectedTopic = nil }
        metadata.setTopicArchived(id: topic.id, true)
    }

    private func restoreTopic(_ topic: TrackPref) {
        metadata.setTopicArchived(id: topic.id, false)
    }

    private func confirmDeleteTopic(_ topic: TrackPref) {
        let doomed = PaperStore.shared.paperIdsSolelyInTopic(topic.name).count
        let message = doomed == 0
            ? L10n.pick(
                "No papers belong only to this topic, so none are deleted. Papers also tagged with other topics keep them.",
                "没有仅属于该主题的论文，因此不会删除任何论文；同时带有其他主题的论文会保留。")
            : L10n.pick(
                "\(doomed) paper(s) belonging only to \"\(topic.name)\" will be permanently deleted. Papers also tagged with other topics are kept. This cannot be undone.",
                "有 \(doomed) 篇仅属于「\(topic.name)」的论文将被永久删除；同时带有其他主题的论文会保留。此操作不可撤销。")
        NotificationCenter.shared.present(AlertItem(
            title: L10n.pick("Delete topic \"\(topic.name)\"?", "删除主题「\(topic.name)」？"),
            message: message,
            actions: [
                .confirm(L10n.pick("Delete", "删除"), isDestructive: true, action: {
                    if selectedTopic == topic.name { selectedTopic = nil }
                    PaperStore.shared.purgeTopicPapers(topic.name)
                    metadata.deleteTopic(id: topic.id)
                }),
                .cancel(L10n.pick("Cancel", "取消"))
            ],
            textFieldValue: nil,
            textFieldLabel: nil
        ))
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
        selectedCollectionId = collection.id
        selectedItem = nil
    }

    private func startNewRoot() {
        guard let c = PaperStore.shared.createCollection(name: "Untitled") else { return }
        editingCollectionId = c.id
        editingCollectionName = c.name
    }

    private func startNewSubfolder(_ parent: PaperCollection) {
        expandedCollections.insert(parent.id)
        guard let c = PaperStore.shared.createCollection(name: "Untitled", parentId: parent.id) else { return }
        editingCollectionId = c.id
        editingCollectionName = c.name
    }

    private func commitCollectionRename() {
        guard let id = editingCollectionId else { return }
        let name = editingCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            PaperStore.shared.renameCollection(id: id, to: name)
        }
        editingCollectionId = nil
    }

    private func confirmDelete(_ target: PaperCollection) {
        NotificationCenter.shared.present(AlertItem(
            title: "Delete \"\(target.name)\"?",
            message: "This also deletes its subfolders. Your papers stay in the library.",
            actions: [
                .confirm("Delete", isDestructive: true, action: {
                    let subtree = PaperStore.shared.collectionSubtreeIds(target.id)
                    if let sel = selectedCollectionId, subtree.contains(sel) {
                        selectedCollectionId = nil
                    }
                    PaperStore.shared.deleteCollection(id: target.id)
                }),
                .cancel("Cancel")
            ],
            textFieldValue: nil,
            textFieldLabel: nil
        ))
    }
}

enum TagFilterState {
    case neutral
    case include
    case exclude
}

/// The "show everything" reset chip. Neutral until no filter is active, then
/// fills with the accent color — distinct from the per-tag colored chips so it
/// reads as a control rather than a tag.
private struct AllTagsChip: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("All")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? .white : .primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.20), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

/// A per-tag colored filter chip in the FacetX style: a faded `#` prefix and
/// the tag in its deterministic palette color. Cycling drives the three states
/// — neutral (tinted), include (solid fill), exclude (dashed, struck through).
private struct TagFilterChip: View {
    let tag: String
    let state: TagFilterState
    let action: () -> Void

    private var color: Color { LabelColor.forTag(tag) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(state == .exclude ? "−" : "#")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(prefixColor)
                Text(tag)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textColor)
                    .strikethrough(state == .exclude)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(strokeColor,
                            style: StrokeStyle(lineWidth: state == .exclude ? 1 : 0.5,
                                               dash: state == .exclude ? [2.5, 2] : []))
            )
        }
        .buttonStyle(.plain)
    }

    private var prefixColor: Color {
        switch state {
        case .include: return Color.white.opacity(0.85)
        case .exclude: return color.opacity(0.85)
        case .neutral: return color.opacity(0.70)
        }
    }

    private var textColor: Color {
        switch state {
        case .include: return .white
        case .exclude: return color.opacity(0.60)
        case .neutral: return .primary
        }
    }

    private var fillColor: Color {
        switch state {
        case .include: return color
        case .exclude: return color.opacity(0.06)
        case .neutral: return color.opacity(0.14)
        }
    }

    private var strokeColor: Color {
        switch state {
        case .include: return color
        case .exclude: return color.opacity(0.55)
        case .neutral: return color.opacity(0.20)
        }
    }
}

/// FacetX-style topic row: a rounded tinted glyph badge, the topic name, and a
/// keyword/query subtitle. Tapping toggles the topic filter; right-click edits,
/// archives, or deletes. Archived rows are dimmed and offer Restore instead.
private struct TopicSidebarRow: View {
    let topic: TrackPref
    let isSelected: Bool
    let isArchived: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    private var subtitle: String {
        if !topic.query.isEmpty { return topic.query }
        return topic.keywords.prefix(3).joined(separator: " · ")
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                TopicBadge(color: topic.resolvedColor, icon: topic.displayIcon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The selection fill is drawn at the row-cell level via
            // `.listRowBackground` (see the call site) so it spans the same
            // width as the native sidebar selection (Library), not just the
            // inset content area.
            .opacity(isArchived ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isArchived {
                Button("Restore") { onRestore() }
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            } else {
                Button("Edit…") { onEdit() }
                Button("Archive") { onArchive() }
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
    }
}

/// One collection row plus its (lazily expanded) descendants.
private struct CollectionTreeRow: View {
    let collection: PaperCollection
    let depth: Int
    let childrenByParent: [String: [PaperCollection]]
    @Binding var expanded: Set<String>
    let selectedCollectionId: String?
    let papers: [Paper]
    @Binding var editingCollectionId: String?
    @Binding var editingCollectionName: String
    let onSelect: (PaperCollection) -> Void
    let onCommitRename: () -> Void
    let onAddSubfolder: (PaperCollection) -> Void
    let onDelete: (PaperCollection) -> Void

    @FocusState private var renameFocused: Bool

    private var children: [PaperCollection] { childrenByParent[collection.id] ?? [] }
    private var hasChildren: Bool { !children.isEmpty }
    private var isExpanded: Bool { expanded.contains(collection.id) }
    private var isSelected: Bool { selectedCollectionId == collection.id }
    private var isEditing: Bool { editingCollectionId == collection.id }

    private var paperCount: Int {
        let ids = subtreeIds(for: collection.id)
        return papers.filter { $0.collectionIds.contains(where: ids.contains) }.count
    }

    private func subtreeIds(for id: String) -> Set<String> {
        var result: Set<String> = [id]
        for child in childrenByParent[id] ?? [] {
            result.formUnion(subtreeIds(for: child.id))
        }
        return result
    }

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
                    papers: papers,
                    editingCollectionId: $editingCollectionId,
                    editingCollectionName: $editingCollectionName,
                    onSelect: onSelect,
                    onCommitRename: onCommitRename,
                    onAddSubfolder: onAddSubfolder,
                    onDelete: onDelete
                )
            }
        }
    }

    private var row: some View {
        HStack(spacing: 5) {
            disclosure
            HStack(spacing: 8) {
                CollectionBadge(color: collection.resolvedColor, size: 22)
                if isEditing {
                    TextField("", text: $editingCollectionName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .focused($renameFocused)
                        .onSubmit { onCommitRename() }
                        .onExitCommand { editingCollectionId = nil }
                        .onChange(of: renameFocused) { _, focused in
                            if focused {
                                // Select all text once the field is first responder
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 30_000_000)
                                    NSApp.keyWindow?.selectAll(nil)
                                }
                            } else if editingCollectionId == collection.id {
                                onCommitRename()
                            }
                        }
                        .task(id: isEditing) {
                            if isEditing { renameFocused = true }
                        }
                } else {
                    Text(collection.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .onTapGesture(count: 2) {
                            editingCollectionId = collection.id
                            editingCollectionName = collection.name
                        }
                }
                Spacer(minLength: 0)
                if !isEditing && paperCount > 0 {
                    Text("\(paperCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            isSelected ? Color.white.opacity(0.20) : Color.secondary.opacity(0.12),
                            in: Capsule()
                        )
                }
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onSelect(collection) }
        }
        .padding(.leading, CGFloat(depth) * 14)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu { contextMenu }
        .listRowBackground(rowBackground)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(NSColor.selectedContentBackgroundColor))
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
        } else {
            Color.clear
        }
    }

    private var disclosure: some View {
        Group {
            if hasChildren {
                Button {
                    if isExpanded { expanded.remove(collection.id) }
                    else { expanded.insert(collection.id) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
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
        Button("Rename") {
            editingCollectionId = collection.id
            editingCollectionName = collection.name
        }
        Button("New Subfolder…") { onAddSubfolder(collection) }
        Menu("Color") {
            ForEach(LabelColor.allCases) { c in
                Button(c.title) {
                    PaperStore.shared.setCollectionColor(id: collection.id, color: c.rawValue)
                }
            }
            Divider()
            Button("Default") {
                PaperStore.shared.setCollectionColor(id: collection.id, color: nil)
            }
        }
        Divider()
        Button("Delete", role: .destructive) { onDelete(collection) }
    }
}

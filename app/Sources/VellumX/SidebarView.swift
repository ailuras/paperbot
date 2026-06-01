import SwiftUI

struct SidebarView: View {
    @Binding var selectedItem: SidebarItem?
    @Binding var selectedTopic: String?
    @Binding var includedTags: Set<String>
    @Binding var excludedTags: Set<String>
    let tags: [String]
    var metadata: MetadataStore
    let statusMessage: String

    var body: some View {
        List(selection: $selectedItem) {
            Section("Library") {
                ForEach([SidebarItem.recommended, .pending, .starred, .read, .skipped, .all], id: \.self) { item in
                    NavigationLink(value: item) {
                        Label {
                            Text(item.displayName)
                        } icon: {
                            Image(systemName: item.iconName)
                                .foregroundStyle(item.iconColor)
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
                    TagFilterChip(
                        title: "All Tags",
                        state: includedTags.isEmpty && excludedTags.isEmpty ? .include : .neutral
                    ) {
                        includedTags.removeAll()
                        excludedTags.removeAll()
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            TagFilterChip(title: "#\(tag)", state: tagState(tag)) {
                                cycleTag(tag)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if !statusMessage.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
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
            HStack(spacing: 5) {
                if state == .include {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                } else if state == .exclude {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                }

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .cornerRadius(9)
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

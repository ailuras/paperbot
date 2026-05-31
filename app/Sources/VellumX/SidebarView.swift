import SwiftUI

struct SidebarView: View {
    @Binding var selectedItem: SidebarItem?
    @Binding var selectedTopic: String?
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
}

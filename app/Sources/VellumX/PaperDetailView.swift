import SwiftUI
import AppKit

// MARK: - Paper Detail View

struct PaperDetailView: View {
    let paper: Paper
    private var metadata: MetadataStore { .shared }
    @Binding var isTranslating: Bool
    @Binding var isResolvingPdf: Bool
    @Binding var statusMessage: String

    let onTranslate: (Paper) -> Void
    let onResolvePdf: (Paper) -> Void

    @FocusState private var noteFocused: Bool

    // Status configuration
    private let statuses: [(PaperStatus, String, Color)] = [
        (.pending,     "clock",        .blue),
        (.recommended, "sparkles",     .orange),
        (.read,        "checkmark.circle", .green),
        (.starred,     "star.fill",    .yellow),
        (.skip,        "eye.slash",    .secondary)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: Header Card
                headerCard

                Divider().padding(.horizontal, 20)

                // MARK: Action Buttons
                actionBar

                Divider().padding(.horizontal, 20)

                // MARK: Abstract
                abstractSection

                // MARK: Translation
                if !paper.abstractZh.isEmpty || isTranslating {
                    translationSection
                }

                // MARK: Notes
                notesSection
            }
            .padding(.vertical, 16)
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Meta row: Venue | Date | Track | Score
            HStack(spacing: 8) {
                Text(paper.venueAbbr)
                    .font(.caption.bold())
                    .foregroundColor(metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr)))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr)).opacity(0.12))
                    .cornerRadius(4)

                if !paper.publicationDate.isEmpty {
                    Text(paper.publicationDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !paper.track.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(topics, id: \.self) { topic in
                            Text(topic)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(metadata.topicColor(topic).opacity(0.12))
                                .foregroundColor(metadata.topicColor(topic))
                                .cornerRadius(4)
                        }
                    }
                }

                ScoreBadgeView(score: paper.score, color: metadata.tierColor(paper.tier))
            }

            // Title
            Text(paper.title)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .lineSpacing(3)
                .foregroundColor(.primary)

            // Authors
            if !paper.authors.isEmpty {
                Text(paper.authors.joined(separator: ", "))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var topics: [String] {
        paper.track.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            ForEach(Array(statuses.enumerated()), id: \.offset) { index, item in
                let (status, icon, color) = item
                let isActive = paper.status == status

                Button {
                    PaperStore.shared.setPaperStatus(id: paper.id, status: status)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(statusLabel(for: status))
                            .font(.system(size: 12, weight: isActive ? .bold : .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isActive ? color.opacity(0.18) : Color.clear)
                    .foregroundColor(isActive ? color : .secondary)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isActive ? color.opacity(0.4) : Color.gray.opacity(0.25), lineWidth: isActive ? 1.5 : 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func statusLabel(for status: PaperStatus) -> String {
        status.displayName
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusBar

            HStack(spacing: 10) {
                DetailActionButton(
                    icon: "doc.text",
                    label: "Open PDF",
                    isLoading: isResolvingPdf,
                    action: { onResolvePdf(paper) }
                )

                DetailActionButton(
                    icon: "character.book.closed",
                    label: "Translate",
                    isLoading: isTranslating,
                    action: { onTranslate(paper) }
                )

                if let doi = paper.doi, !doi.isEmpty {
                    Link(destination: URL(string: doi)!) {
                        DetailActionButtonContent(icon: "link", label: "DOI Link", isLoading: false)
                    }
                    .buttonStyle(.plain)
                } else if let url = URL(string: paper.landingPageUrl), !paper.landingPageUrl.isEmpty {
                    Link(destination: url) {
                        DetailActionButtonContent(icon: "link", label: "Open Link", isLoading: false)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Abstract Section

    private var abstractSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "text.alignleft", title: "Abstract")

            Text(paper.abstract.isEmpty ? "No abstract available." : paper.abstract)
                .font(.system(size: 14, design: .serif))
                .lineSpacing(4)
                .foregroundColor(paper.abstract.isEmpty ? .secondary : .primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Translation Section

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "character", title: "Translation")

            if isTranslating {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Translating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !paper.abstractZh.isEmpty {
                Text(paper.abstractZh)
                    .font(.system(size: 14, design: .serif))
                    .lineSpacing(4)
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.yellow.opacity(0.04))
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "square.and.pencil", title: "Notes")

            TextEditor(text: Binding(
                get: { paper.note },
                set: { newValue in
                    paper.note = newValue
                }
            ))
            .focused($noteFocused)
            .font(.system(size: 13))
            .lineSpacing(3)
            .frame(minHeight: 120, maxHeight: .infinity)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(noteFocused ? 0.4 : 0.2), lineWidth: 1)
            )
            .onChange(of: noteFocused) {
                if !noteFocused {
                    PaperStore.shared.setPaperNote(id: paper.id, note: paper.note)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Empty Detail View

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))

            Text("Select a paper to view details")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("Choose an item from the list to read its abstract,\nadd notes, or open the PDF.")
                .font(.callout)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Supporting Views

private struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)
        }
    }
}

private struct DetailActionButtonContent: View {
    let icon: String
    let label: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
        .foregroundColor(.primary)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
        )
    }
}

private struct DetailActionButton: View {
    let icon: String
    let label: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DetailActionButtonContent(icon: icon, label: label, isLoading: isLoading)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct RulesSettingsTab: View {
    @State private var metadata = MetadataStore.shared
    @State private var venueRefreshMessage = ""
    @State private var showPresetConfirm = false
    @State private var importExportMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox(L10n.t(.interestsTracks)) {
                    TracksEditor(tracks: $metadata.topics)
                        .padding(6)
                }

                GroupBox(L10n.t(.venueRatings)) {
                    VStack(alignment: .leading, spacing: 10) {
                        VenuesEditor(venues: $metadata.venues)

                        Divider()

                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t(.applyVenueChanges))
                                    .font(.subheadline.weight(.semibold))
                                Text(L10n.t(.venueChangesHint))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if !venueRefreshMessage.isEmpty {
                                Text(venueRefreshMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                let changed = PaperStore.shared.refreshVenueMetadata()
                                venueRefreshMessage = "\(L10n.t(.venueChangesApplied)) \(changed)"
                            } label: {
                                Label(L10n.t(.applyVenueChanges), systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(6)
                }

                GroupBox(L10n.t(.tierSettings)) {
                    TiersEditor(tiers: $metadata.tiers)
                        .padding(6)
                }

                GroupBox(L10n.t(.citationScoring)) {
                    CitationCurveEditor(
                        breakpoints: $metadata.citationBreakpoints,
                        maxPoints: $metadata.maxCitationPoints
                    )
                    .padding(6)
                }

                Divider()

                // Import / Export / Preset
                HStack(spacing: 12) {
                    Button {
                        importRules()
                    } label: {
                        Label(L10n.t(.importRules), systemImage: "square.and.arrow.down")
                    }

                    Button {
                        exportRules()
                    } label: {
                        Label(L10n.t(.exportRules), systemImage: "square.and.arrow.up")
                    }

                    Spacer()

                    if !importExportMessage.isEmpty {
                        Text(importExportMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        showPresetConfirm = true
                    } label: {
                        Label(L10n.t(.usePreset), systemImage: "arrow.counterclockwise")
                    }
                    .alert(L10n.t(.usePresetTitle), isPresented: $showPresetConfirm) {
                        Button(L10n.t(.cancel), role: .cancel) {}
                        Button(L10n.t(.confirm), role: .destructive) {
                            metadata.resetToPreset()
                            importExportMessage = ""
                        }
                    } message: {
                        Text(L10n.t(.usePresetMessage))
                    }
                }
            }
            .padding()
        }
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            try metadata.importMetadata(from: data)
            importExportMessage = L10n.t(.importSuccess)
        } catch {
            importExportMessage = "\(L10n.t(.importFailed)) \(error.localizedDescription)"
        }
    }

    private func exportRules() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "vellumx-rules.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try metadata.exportMetadata()
            try data.write(to: url, options: .atomic)
            importExportMessage = "Exported to \(url.lastPathComponent)"
        } catch {
            importExportMessage = "\(L10n.t(.importFailed)) \(error.localizedDescription)"
        }
    }
}

// MARK: - TiersEditor

struct TiersEditor: View {
    @Binding var tiers: [TierPref]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.t(.tierRank))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                Text(L10n.t(.name))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.t(.tierPointsValue))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                Spacer().frame(width: 20)
            }

            ForEach($tiers) { $tier in
                HStack(spacing: 8) {
                    Text("\(tier.rank)")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .leading)
                    TextField(L10n.t(.name), text: $tier.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                    TextField("", value: $tier.points, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    Button(role: .destructive) {
                        tiers.removeAll { $0.rank == tier.rank }
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                }
            }

            Button {
                let nextRank = (tiers.map(\.rank).max() ?? 0) + 1
                tiers.append(TierPref(
                    rank: nextRank,
                    name: "Tier \(nextRank)",
                    points: max(1, 12 - 2 * nextRank),
                    color: nil,
                    sortOrder: tiers.count
                ))
            } label: { Label(L10n.t(.addTier), systemImage: "plus") }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - CitationCurveEditor

struct CitationCurveEditor: View {
    @Binding var breakpoints: [CitationBreakpoint]
    @Binding var maxPoints: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t(.citationScoringHint))
                .font(.caption)
                .foregroundStyle(.secondary)

            if breakpoints.isEmpty {
                Text(L10n.t(.noBreakpoints))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                HStack(spacing: 8) {
                    Text(L10n.t(.breakpointUpTo))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Text(L10n.t(.pointsPerCitation))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Spacer().frame(width: 20)
                }

                ForEach(breakpoints.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        if breakpoints[index].up_to != nil {
                            TextField("", value: upToBinding(for: index), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        } else {
                            Text(L10n.t(.noCap))
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .leading)
                        }

                        TextField("", value: $breakpoints[index].points_per_citation, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)

                        // Toggle cap button
                        Button {
                            if breakpoints[index].up_to != nil {
                                breakpoints[index].up_to = nil
                            } else {
                                breakpoints[index].up_to = 100
                            }
                        } label: {
                            Image(systemName: breakpoints[index].up_to != nil ? "infinity" : "number")
                                .help(breakpoints[index].up_to != nil ? L10n.t(.noCap) : L10n.t(.breakpointUpTo))
                        }
                        .buttonStyle(.borderless)

                        Button(role: .destructive) {
                            breakpoints.remove(at: index)
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    Text(L10n.t(.maxCitationPointsLabel))
                        .font(.subheadline)
                    TextField("", value: $maxPoints, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                .padding(.top, 4)
            }

            Button {
                breakpoints.append(CitationBreakpoint(up_to: nil, points_per_citation: 1.0))
            } label: { Label(L10n.t(.addBreakpoint), systemImage: "plus") }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func upToBinding(for index: Int) -> Binding<Int> {
        Binding(
            get: { breakpoints[index].up_to ?? 0 },
            set: { breakpoints[index].up_to = $0 }
        )
    }
}

// MARK: - TracksEditor

struct TracksEditor: View {
    @Binding var tracks: [TrackPref]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if tracks.isEmpty {
                Text(L10n.t(.noTracks)).font(.caption).foregroundStyle(.secondary)
            }
            ForEach($tracks) { $track in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField(L10n.t(.name), text: $track.name)
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            tracks.removeAll { $0.id == track.id }
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                    TextField(L10n.t(.searchQuery), text: $track.query)
                        .textFieldStyle(.roundedBorder)
                    TextField(L10n.t(.keywordsCSV), text: keywordsBinding(for: $track))
                        .textFieldStyle(.roundedBorder)
                    Divider()
                }
            }
            Button {
                tracks.append(TrackPref(name: L10n.t(.newTrack), query: "", keywords: []))
            } label: { Label(L10n.t(.addTrack), systemImage: "plus") }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keywordsBinding(for track: Binding<TrackPref>) -> Binding<String> {
        Binding(
            get: { track.wrappedValue.keywords.joined(separator: ", ") },
            set: { newValue in
                track.wrappedValue.keywords = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

// MARK: - VenuesEditor

struct VenuesEditor: View {
    @Binding var venues: [VenuePref]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if venues.isEmpty {
                Text(L10n.t(.noVenues)).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(L10n.t(.abbr)).font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                Text(L10n.t(.field)).font(.caption).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                Text(L10n.t(.matchPhrase)).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.t(.tier)).font(.caption).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                Spacer().frame(width: 20)
            }
            ForEach($venues) { $venue in
                HStack(spacing: 8) {
                    TextField(L10n.t(.abbr), text: $venue.abbr)
                        .textFieldStyle(.roundedBorder).frame(width: 64)
                    TextField(L10n.t(.field), text: fieldBinding(for: $venue))
                        .textFieldStyle(.roundedBorder).frame(width: 56)
                    TextField(L10n.t(.matchPhrase), text: $venue.phrase)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    Picker("", selection: $venue.tier) {
                        ForEach(1...5, id: \.self) { Text("\(L10n.t(.tier)) \($0)").tag($0) }
                    }
                    .labelsHidden().frame(width: 84)
                    Button(role: .destructive) {
                        venues.removeAll { $0.id == venue.id }
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                venues.append(VenuePref(abbr: "", phrase: "", tier: 3, field: ""))
            } label: { Label(L10n.t(.addVenue), systemImage: "plus") }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldBinding(for venue: Binding<VenuePref>) -> Binding<String> {
        Binding(
            get: { venue.wrappedValue.field ?? "" },
            set: { venue.wrappedValue.field = $0.isEmpty ? nil : $0 }
        )
    }
}


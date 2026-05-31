import SwiftUI

struct PapersSettingsTab: View {
    @State private var settings = AppSettings.shared
    @State private var venueRefreshMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox(L10n.t(.dailyRecommendations)) {
                    VStack(spacing: 10) {
                        stepperRow(L10n.t(.dailyCount), value: $settings.dailyCount, in: 1...20)
                        stepperRow(L10n.t(.qualitySlots), value: $settings.qualitySlots, in: 0...20)
                        stepperRow(L10n.t(.highScoreThreshold), value: $settings.highScoreThreshold, in: 0...100)
                        stepperRow(L10n.t(.recentWindow), value: $settings.recentDays, in: 1...365)
                    }
                    .padding(8)
                }

                GroupBox(L10n.t(.openAlexFetch)) {
                    VStack(alignment: .leading, spacing: 8) {
                        labeledField(L10n.t(.contactEmail), text: $settings.openAlexMailto)
                        labeledNumber(L10n.t(.perPage), value: $settings.perPage)
                        labeledNumber(L10n.t(.fetchDays), value: $settings.defaultDays)
                        labeledNumber(L10n.t(.maxResults), value: $settings.defaultMaxResults)
                        labeledField(L10n.t(.topicFilter), text: $settings.topicFilter)
                    }
                    .padding(6)
                }

                GroupBox(L10n.t(.interestsTracks)) {
                    TracksEditor(tracks: $settings.tracks)
                        .padding(6)
                }

                GroupBox(L10n.t(.venueRatings)) {
                    VStack(alignment: .leading, spacing: 10) {
                        VenuesEditor(venues: $settings.venues)

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
            }
            .padding()
        }
    }

    private func stepperRow(_ label: String, value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("", value: clamped(value, to: range), format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .textFieldStyle(.roundedBorder)
            Stepper("", value: value, in: range)
                .labelsHidden()
                .controlSize(.mini)
        }
    }

    private func clamped(_ value: Binding<Int>, to range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).frame(width: 130, alignment: .leading)
            TextField("", text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func labeledNumber(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label).frame(width: 130, alignment: .leading)
            TextField("", value: value, format: .number).textFieldStyle(.roundedBorder)
        }
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

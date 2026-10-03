import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var tracker: Tracker
    @Environment(\.openURL) private var openURL
    @AppStorage(Retention.storageKey) private var retention = Retention.forever.rawValue
    @State private var confirmClear = false
    @State private var query = ""

    /// Plays whose title, artist or service matches every word of the search.
    private var matches: [HistoryEntry] {
        let words = query.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return store.allHistory }
        return store.allHistory.filter { e in
            let text = "\(e.title) \(e.artist) \(WebLink.label(e.source ?? "ios"))"
            return words.allSatisfy { text.localizedStandardContains($0) }
        }
    }

    /// Newest day first, newest play first within a day.
    private var sections: [(day: Date, entries: [HistoryEntry])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: matches) { cal.startOfDay(for: $0.at) }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day]!.sorted { $0.at > $1.at })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.allHistory.isEmpty {
                    Text("Songs you listen to will be listed here, one line per play.")
                        .foregroundStyle(.secondary)
                } else if sections.isEmpty {
                    Text("No plays match “\(query)”.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sections, id: \.day) { section in
                    Section {
                        ForEach(section.entries) { e in
                            HStack(spacing: 12) {
                                ArtworkView(id: e.trackID, size: 42, remoteURL: e.source.flatMap {
                                    WebLink.thumbnail(source: $0, key: e.trackID, artwork: e.artwork)
                                })
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(e.source.map { "\(e.artist) · \(WebLink.label($0))" } ?? e.artist)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(e.at.formatted(date: .omitted, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let source = e.source {
                                    if let url = WebLink.track(source: source, key: e.trackID, title: e.title, artist: e.artist) {
                                        openURL(url)
                                    }
                                } else {
                                    tracker.play(id: e.trackID)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(dayLabel(section.day))
                            Spacer()
                            Text("\(section.entries.count) plays")
                        }
                    }
                }
            }
            .navigationTitle("History")
            .searchable(text: $query, prompt: "Songs, artists or services")
            .pageBottomMargin()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Keep history", selection: $retention) {
                            ForEach(Retention.allCases) { r in Text(r.label).tag(r.rawValue) }
                        }
                        Button("Clear history", role: .destructive) { confirmClear = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Clear the listening history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { store.clearHistory() }
            }
        }
    }
}

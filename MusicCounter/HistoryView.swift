import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var tracker: Tracker
    @AppStorage(Retention.storageKey) private var retention = Retention.forever.rawValue
    @State private var confirmClear = false

    /// Newest day first, newest play first within a day.
    private var sections: [(day: Date, entries: [HistoryEntry])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: store.stats.history) { cal.startOfDay(for: $0.at) }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day]!.sorted { $0.at > $1.at })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.stats.history.isEmpty {
                    Text("Songs you listen to will be listed here, one line per play.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sections, id: \.day) { section in
                    Section {
                        ForEach(section.entries) { e in
                            HStack(spacing: 12) {
                                ArtworkView(id: e.trackID, size: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(e.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(e.at.formatted(date: .omitted, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { tracker.play(id: e.trackID) }
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

import SwiftUI
import Charts
import MediaPlayer

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var tracker: Tracker
    @EnvironmentObject var sync: Sync
    @AppStorage(Retention.storageKey) private var retention = Retention.forever.rawValue
    @State private var confirmReset = false
    @State private var sharing = false
    @State private var sortByPlays = false
    @State private var servicesToday = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !tracker.authorized { permissionCard }
                    if let error = sync.error { syncErrorCard(error) }
                    VStack(spacing: 16) {
                        heroCard
                        statRow
                        weekCard
                        servicesCard
                        topTracksCard
                        favoritesCard
                        artistsCard
                    }
                }
                .padding(.horizontal, 16)
            }
            .pageBottomMargin()
            .refreshable { tracker.reconcile() }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Music Counter")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { sharing = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share your listening")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Keep history", selection: $retention) {
                            ForEach(Retention.allCases) { r in Text(r.label).tag(r.rawValue) }
                        }
                        syncMenu
                        Button("Reset stats", role: .destructive) { confirmReset = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Erase this phone's stats? Favorites, achievements and other devices' stats are kept.", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Erase", role: .destructive) { store.reset() }
            }
            .sheet(isPresented: $sharing) { ShareSheet() }
        }
    }

    // MARK: - Sections

    @ViewBuilder private var syncMenu: some View {
        Section("Sync with browser") {
            if !Sync.isConfigured {
                Text("Add GoogleService-Info.plist to enable")
            } else if let email = sync.email {
                Text(email)
                if !sync.otherDevices.isEmpty {
                    Text("With \(sync.otherDevices.joined(separator: ", "))")
                }
                Button { sync.push(force: true) } label: { Label("Sync now", systemImage: "arrow.triangle.2.circlepath") }
                Button { sync.signOut() } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
            } else {
                Button {
                    Task { await sync.signIn() }
                } label: {
                    Label("Sign in with Google", systemImage: "person.crop.circle")
                }
            }
        }
    }

    private func syncErrorCard(_ message: String) -> some View {
        Card {
            Label("Sync problem", systemImage: "exclamationmark.icloud.fill").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var permissionCard: some View {
        Card {
            Label("Library access needed", systemImage: "lock.fill").font(.headline)
            Text("Allow Media & Apple Music access in Settings so the app can count your listening.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var heroCard: some View {
        let goal = store.dailyGoal
        let today = store.todaySeconds
        return Card {
            HStack(spacing: 20) {
                ZStack {
                    ProgressRing(progress: today / goal, segments: todayServiceSegments)
                    VStack(spacing: 0) {
                        Text(formatDuration(today)).font(.title2.bold()).monospacedDigit()
                        Text("listened today").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 130, height: 130)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily goal").font(.caption).foregroundStyle(.secondary)
                    Text(formatDuration(goal)).font(.title3.bold())
                    Text("Yesterday + 1 h").font(.caption2).foregroundStyle(.secondary)
                    if today >= goal {
                        Label("Goal reached", systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(.green)
                    } else {
                        Text("\(formatDuration(goal - today)) to go")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if store.streak > 0 {
                        Label("\(store.streak)-day streak", systemImage: "flame.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.gradient)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Today's listening split by service, in the service colours, for the goal ring.
    private var todayServiceSegments: [(color: Color, share: Double)] {
        Service.ordered(store.lastDays(1).last?.services ?? [:]).map { (Service.color($0.key), $0.value) }
    }

    private var statRow: some View {
        HStack(spacing: 12) {
            statTile("Past 7 days", formatDuration(pastDays(7)), "calendar")
            statTile("Past 30 days", formatDuration(pastDays(30)), "calendar.circle.fill")
            statTile("All time", formatDuration(store.totalSeconds), "clock.fill")
        }
    }

    private func statTile(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.footnote).foregroundStyle(Theme.gradient)
            Text(value).font(.title3.bold()).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var weekCard: some View {
        let days = store.lastDays(7)
        return Card(title: "Last 7 days") {
            DaysChart(days: days, weekdayLabels: true)
                .frame(height: 150)
            Text("Total \(formatDuration(days.reduce(0) { $0 + $1.seconds }))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var servicesCard: some View {
        Card(title: "By service") {
            Picker("Scope", selection: $servicesToday) {
                Text("Today").tag(true)
                Text("All time").tag(false)
            }
            .pickerStyle(.segmented)
            ServiceBreakdown(services: servicesToday ? store.services(lastDays: 1) : store.services,
                             key: servicesToday ? "today" : "all")
        }
    }

    /// Today plus the days before it.
    private func pastDays(_ n: Int) -> Double {
        store.lastDays(n).reduce(0) { $0 + $1.seconds }
    }

    private var topTracksCard: some View {
        let all = store.allTracks
        let sorted = sortByPlays
            ? all.sorted { ($0.plays, $0.seconds) > ($1.plays, $1.seconds) }
            : all.sorted { $0.seconds > $1.seconds }
        let shown = Array(sorted.prefix(5))
        let maxValue = sortByPlays ? Double(sorted.first?.plays ?? 1) : (sorted.first?.seconds ?? 1)

        return Card(title: "Top tracks") {
            Picker("Sort", selection: $sortByPlays) {
                Text("Time").tag(false)
                Text("Plays").tag(true)
            }
            .pickerStyle(.segmented)

            if shown.isEmpty {
                Text("Play some music from your library and it will show up here.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, t in
                let value = sortByPlays ? Double(t.plays) : t.seconds
                TrackRow(track: t, rank: index + 1, ratio: maxValue > 0 ? value / maxValue : 0)
            }
        }
    }

    private var favoritesCard: some View {
        let favs = store.favoriteTracks
        return Card(title: "Favorites") {
            if favs.isEmpty {
                Text("Tap the star on a song to keep it here. Favorites survive Reset.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(favs) { t in
                TrackRow(track: t)
            }
        }
    }

    private var artistsCard: some View {
        let all = store.artists
        let shown = Array(all.prefix(5))
        let maxSeconds = all.first?.seconds ?? 1
        return Card(title: "Top artists") {
            if shown.isEmpty {
                Text("No artists yet.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(shown.enumerated()), id: \.element.name) { index, a in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(a.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        GeometryReader { geo in
                            Capsule().fill(Theme.gradient)
                                .frame(width: geo.size.width * CGFloat(maxSeconds > 0 ? a.seconds / maxSeconds : 0))
                        }
                        .frame(height: 3)
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatDuration(a.seconds)).font(.subheadline.weight(.medium)).monospacedDigit()
                        Text("\(a.plays)×").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { tracker.play(artist: a.name) }
            }
        }
    }
}

struct DaysChart: View {
    let days: [DayListening]
    var weekdayLabels = false
    /// When set, tapping a column selects its day (tapping it again clears it).
    var selection: Binding<Date?>? = nil
    @State private var grown = false

    private struct Segment: Identifiable {
        var date: Date
        var source: String
        var seconds: Double
        var id: String { "\(date.timeIntervalSince1970)-\(source)" }
    }

    var body: some View {
        let segments = days.flatMap { day in
            Service.ordered(day.services).map { Segment(date: day.date, source: $0.key, seconds: $0.value) }
        }
        let first = days.first?.date ?? Date()
        let end = Calendar.current.date(byAdding: .day, value: 1, to: days.last?.date ?? first) ?? first
        // Fixed while the columns grow, or the axis would rescale under them.
        let peak = days.map { $0.seconds / 60 }.max() ?? 0
        Chart(segments) { seg in
            BarMark(
                x: .value("Day", seg.date, unit: .day),
                y: .value("Minutes", grown ? seg.seconds / 60 : 0)
            )
            .cornerRadius(2)
            .foregroundStyle(by: .value("Service", Service.label(seg.source)))
            .opacity(opacity(seg.date))
        }
        .serviceColors(segments.map(\.source))
        .chartXScale(domain: first...end)
        .chartYScale(domain: 0...Swift.max(peak, 1))
        .growIn($grown, key: "\(first.timeIntervalSince1970)-\(days.count)")
        .chartOverlay { proxy in
            if let selection {
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            let x = location.x - geo[proxy.plotAreaFrame].origin.x
                            guard let date = proxy.value(atX: x, as: Date.self) else { return }
                            let day = Calendar.current.startOfDay(for: date)
                            guard days.contains(where: { $0.date == day }) else { return }
                            selection.wrappedValue = selection.wrappedValue == day ? nil : day
                        }
                }
            }
        }
        .chartXAxis {
            if weekdayLabels {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            } else if days.count > 90 {
                // A year of days: label every other month, a day label would crowd.
                AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: days.count > 35 ? 14 : 7)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
    }

    private func opacity(_ date: Date) -> Double {
        if let selected = selection?.wrappedValue { return date == selected ? 1 : 0.3 }
        return Calendar.current.isDateInToday(date) ? 1 : 0.7
    }
}

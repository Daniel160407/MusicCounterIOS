import SwiftUI
import Charts
import MediaPlayer

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var tracker: Tracker
    @EnvironmentObject var sync: Sync
    @AppStorage("goalMinutes") private var goalMinutes = 60
    @AppStorage(Retention.storageKey) private var retention = Retention.forever.rawValue
    @State private var confirmReset = false
    @State private var shareImage: Image?
    @State private var sortByPlays = false
    @State private var servicesToday = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !tracker.authorized { permissionCard }
                    if let error = sync.error { syncErrorCard(error) }
                    heroCard
                    statRow
                    weekCard
                    servicesCard
                    topTracksCard
                    favoritesCard
                    artistsCard
                }
                .padding(.horizontal, 16)
            }
            .pageBottomMargin()
            .refreshable { tracker.reconcile() }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Music Counter")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let shareImage {
                        ShareLink(item: shareImage, preview: SharePreview("My listening", image: shareImage)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Daily goal", selection: $goalMinutes) {
                            ForEach([30, 60, 120, 180, 240], id: \.self) { m in
                                Text(m < 60 ? "\(m) min" : "\(m / 60) h").tag(m)
                            }
                        }
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
            .task(id: store.totalSeconds) { renderShareImage() }
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
        let goal = Double(goalMinutes) * 60
        let today = store.todaySeconds
        return Card {
            HStack(spacing: 20) {
                ZStack {
                    ProgressRing(progress: today / goal)
                    VStack(spacing: 0) {
                        Text(formatDuration(today)).font(.title2.bold()).monospacedDigit()
                        Text("listened today").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 130, height: 130)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily goal").font(.caption).foregroundStyle(.secondary)
                    Text(formatDuration(goal)).font(.title3.bold())
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
            ServiceBreakdown(services: servicesToday ? store.services(lastDays: 1) : store.services)
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

    private func renderShareImage() {
        let renderer = ImageRenderer(content: ShareCardView(store: store).environment(\.colorScheme, .dark))
        renderer.scale = 3
        if let ui = renderer.uiImage { shareImage = Image(uiImage: ui) }
    }
}

struct DaysChart: View {
    let days: [DayListening]
    var weekdayLabels = false
    /// When set, tapping a column selects its day (tapping it again clears it).
    var selection: Binding<Date?>? = nil

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
        Chart(segments) { seg in
            BarMark(
                x: .value("Day", seg.date, unit: .day),
                y: .value("Minutes", seg.seconds / 60)
            )
            .cornerRadius(2)
            .foregroundStyle(by: .value("Service", Service.label(seg.source)))
            .opacity(opacity(seg.date))
        }
        .serviceColors(segments.map(\.source))
        .chartXScale(domain: first...end)
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

/// The picture behind the Share button.
struct ShareCardView: View {
    let store: Store

    var body: some View {
        let all = store.allTracks
        let top = all.sorted { $0.seconds > $1.seconds }.prefix(3)
        VStack(alignment: .leading, spacing: 14) {
            Text("My listening").font(.headline).foregroundStyle(.white.opacity(0.7))
            Text(formatDuration(store.totalSeconds)).font(.system(size: 54, weight: .heavy))
                .foregroundStyle(Theme.gradient)
            Text("\(store.totalPlays) plays · \(all.count) songs · today \(formatDuration(store.todaySeconds))")
                .font(.subheadline).foregroundStyle(.white.opacity(0.7))
            if !top.isEmpty {
                Divider().overlay(.white.opacity(0.2))
                ForEach(Array(top.enumerated()), id: \.element.id) { i, t in
                    HStack {
                        Text("\(i + 1)").bold().frame(width: 20)
                        VStack(alignment: .leading) {
                            Text(t.title).lineLimit(1)
                            Text(t.artist).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                        Spacer()
                        Text(formatDuration(t.seconds)).monospacedDigit()
                    }
                    .foregroundStyle(.white)
                }
            }
            Text("Music Counter").font(.caption.bold()).foregroundStyle(.white.opacity(0.5))
        }
        .padding(28)
        .frame(width: 380, alignment: .leading)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
    }
}

import SwiftUI
import Charts
import MediaPlayer

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var tracker: Tracker
    @AppStorage("goalMinutes") private var goalMinutes = 60
    @AppStorage(Retention.storageKey) private var retention = Retention.forever.rawValue
    @State private var confirmReset = false
    @State private var shareImage: Image?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !tracker.authorized { permissionCard }
                    heroCard
                    statRow
                    weekCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
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
                        Button("Reset stats", role: .destructive) { confirmReset = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Erase all stats? Favorites are kept.", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Erase", role: .destructive) { store.reset() }
            }
            .task(id: store.totalSeconds) { renderShareImage() }
        }
    }

    // MARK: - Sections

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
                        Text("today").font(.caption).foregroundStyle(.secondary)
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
            statTile("All time", formatDuration(store.totalSeconds), "clock.fill")
            statTile("Plays", "\(store.totalPlays)", "play.fill")
            statTile("Songs", "\(store.stats.tracks.count)", "music.note")
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

    private func renderShareImage() {
        let renderer = ImageRenderer(content: ShareCardView(store: store).environment(\.colorScheme, .dark))
        renderer.scale = 3
        if let ui = renderer.uiImage { shareImage = Image(uiImage: ui) }
    }
}

struct DaysChart: View {
    let days: [(date: Date, seconds: Double)]
    var weekdayLabels = false

    var body: some View {
        Chart(days, id: \.date) { day in
            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Minutes", day.seconds / 60)
            )
            .cornerRadius(4)
            .foregroundStyle(Calendar.current.isDateInToday(day.date)
                             ? AnyShapeStyle(Theme.gradient)
                             : AnyShapeStyle(Theme.accent.opacity(0.35)))
        }
        .chartXAxis {
            if weekdayLabels {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
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
}

/// The picture behind the Share button.
struct ShareCardView: View {
    let store: Store

    var body: some View {
        let top = store.stats.tracks.values.sorted { $0.seconds > $1.seconds }.prefix(3)
        VStack(alignment: .leading, spacing: 14) {
            Text("My listening").font(.headline).foregroundStyle(.white.opacity(0.7))
            Text(formatDuration(store.totalSeconds)).font(.system(size: 54, weight: .heavy))
                .foregroundStyle(Theme.gradient)
            Text("\(store.totalPlays) plays · \(store.stats.tracks.count) songs · today \(formatDuration(store.todaySeconds))")
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

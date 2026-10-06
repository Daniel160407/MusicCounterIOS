import SwiftUI
import Charts

struct InsightsView: View {
    @EnvironmentObject var store: Store
    @State private var rangeDays = 7
    /// Whole ranges stepped back from the one ending today, 0 = current.
    @State private var periodsAgo = 0
    @State private var daysAgo = 0
    @State private var allTime = false
    @State private var selectedDay: Date?
    @State private var selectedHour: Int?
    @State private var hoursGrown = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AchievementsCard()
                    daysCard
                    servicesCard
                    hoursCard
                }
                .padding(.horizontal, 16)
            }
            .pageBottomMargin()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Insights")
        }
    }

    private var daysCard: some View {
        let days = store.lastDays(rangeDays, endingDaysAgo: periodsAgo * rangeDays)
        let total = days.reduce(0) { $0 + $1.seconds }
        let active = days.filter { $0.seconds >= 1 }.count
        let atStart = days.first.map { first in store.firstListeningDay.map { first.date <= $0 } ?? true } ?? true
        return Card(title: "Days you listened") {
            Picker("Range", selection: $rangeDays) {
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("9 months").tag(270)
            }
            .pickerStyle(.segmented)

            HStack {
                Button { periodsAgo += 1 } label: { Image(systemName: "chevron.left") }
                    .disabled(atStart)
                    .accessibilityLabel("Previous period")
                Spacer()
                Text(periodLabel(days)).font(.subheadline.weight(.semibold))
                Spacer()
                Button { periodsAgo -= 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(periodsAgo == 0)
                    .accessibilityLabel("Next period")
            }

            DaysChart(days: days, selection: $selectedDay).frame(height: 170)

            if let selectedDay, let day = days.first(where: { $0.date == selectedDay }) {
                ColumnDetail(
                    title: dayLabel(selectedDay),
                    services: day.services,
                    plays: store.allHistory.filter { Calendar.current.isDate($0.at, inSameDayAs: selectedDay) }
                ) { self.selectedDay = nil }
            } else {
                Text("Tap a column for details.").font(.caption).foregroundStyle(.tertiary)
            }

            HStack {
                Text("Total \(formatDuration(total))")
                Spacer()
                Text("Active \(active)/\(rangeDays) days")
                Spacer()
                Text("Avg \(formatDuration(total / Double(max(rangeDays, 1))))/day")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: rangeDays) { _ in selectedDay = nil; periodsAgo = 0 }
        .onChange(of: periodsAgo) { _ in selectedDay = nil }
    }

    private func periodLabel(_ days: [DayListening]) -> String {
        if periodsAgo == 0 {
            return rangeDays == 270 ? "Last 9 months" : "Last \(rangeDays) days"
        }
        guard let first = days.first?.date, let last = days.last?.date else { return "" }
        let style: Date.FormatStyle = rangeDays == 270
            ? .dateTime.month(.abbreviated).year()
            : .dateTime.day().month(.abbreviated)
        return "\(first.formatted(style)) – \(last.formatted(style))"
    }

    private var servicesCard: some View {
        let days = store.lastDays(rangeDays, endingDaysAgo: periodsAgo * rangeDays)
        return Card(title: "By service · \(periodsAgo == 0 ? "last \(rangeDays) days" : periodLabel(days))") {
            ServiceBreakdown(services: store.services(lastDays: rangeDays, endingDaysAgo: periodsAgo * rangeDays),
                             key: "\(rangeDays)-\(periodsAgo)")
        }
    }

    private struct HourSegment: Identifiable {
        var hour: Int
        var source: String
        var seconds: Double
        var id: String { "\(hour)-\(source)" }
    }

    private var hoursCard: some View {
        let split = allTime ? store.allTimeHours : store.hours(daysAgo: daysAgo)
        let hours = split.map { $0.values.reduce(0, +) }
        let segments = split.enumerated().flatMap { hour, services in
            Service.ordered(services).map { HourSegment(hour: hour, source: $0.key, seconds: $0.value) }
        }
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let peak = hours.enumerated().max { $0.element < $1.element }

        return Card(title: "Hours of the day") {
            Picker("Scope", selection: $allTime) {
                Text("Day").tag(false)
                Text("All time").tag(true)
            }
            .pickerStyle(.segmented)

            if !allTime {
                HStack {
                    Button { daysAgo += 1 } label: { Image(systemName: "chevron.left") }
                        .disabled(daysAgo >= 89)
                    Spacer()
                    Text(dayLabel(date)).font(.subheadline.weight(.semibold))
                    Spacer()
                    Button { daysAgo -= 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(daysAgo == 0)
                }
            }

            Chart(segments) { seg in
                BarMark(
                    x: .value("Hour", seg.hour),
                    y: .value("Minutes", hoursGrown ? seg.seconds / 60 : 0)
                )
                .cornerRadius(2)
                .foregroundStyle(by: .value("Service", Service.label(seg.source)))
                .opacity(selectedHour.map { seg.hour == $0 ? 1 : 0.3 } ?? (seg.hour == peak?.offset ? 1 : 0.7))
            }
            .serviceColors(segments.map(\.source))
            .chartXScale(domain: -0.5...23.5)
            .chartYScale(domain: 0...max((peak?.element ?? 0) / 60, 1))
            .growIn($hoursGrown, key: "\(allTime)-\(daysAgo)")
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            let x = location.x - geo[proxy.plotAreaFrame].origin.x
                            guard let value = proxy.value(atX: x, as: Double.self) else { return }
                            let hour = min(max(Int(value.rounded()), 0), 23)
                            selectedHour = selectedHour == hour ? nil : hour
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisValueLabel {
                        if let h = value.as(Int.self) { Text(h == 23 ? "23" : String(format: "%02d", h)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 170)

            if let selectedHour {
                ColumnDetail(
                    title: (allTime ? "All time · " : "\(dayLabel(date)) · ") + hourRange(selectedHour),
                    services: split[selectedHour],
                    plays: store.allHistory.filter {
                        Calendar.current.component(.hour, from: $0.at) == selectedHour
                            && (allTime || Calendar.current.isDate($0.at, inSameDayAs: date))
                    }
                ) { self.selectedHour = nil }
            } else if let peak, peak.element > 0 {
                Text("Busiest hour: \(String(format: "%02d", peak.offset)):00 · \(formatDuration(peak.element))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Nothing recorded for this period.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: daysAgo) { _ in selectedHour = nil }
        .onChange(of: allTime) { _ in selectedHour = nil }
    }

    private func hourRange(_ hour: Int) -> String {
        String(format: "%02d:00–%02d:00", hour, (hour + 1) % 24)
    }
}

/// What made up one tapped column: the time per service and the songs played in it.
private struct ColumnDetail: View {
    let title: String
    let services: [String: Double]
    let plays: [HistoryEntry]
    var close: () -> Void
    @State private var showAll = false

    private struct Song: Identifiable {
        var id: String
        var entry: HistoryEntry
        var count: Int
    }

    var body: some View {
        let total = services.values.reduce(0, +)
        let songs = Self.songs(plays)
        let shown = showAll ? songs : Array(songs.prefix(5))

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(formatDuration(total)).font(.subheadline.weight(.semibold)).monospacedDigit()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close details")
            }

            if total < 1 {
                Text("Nothing played.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Service.ordered(services), id: \.key) { source, seconds in
                HStack(spacing: 8) {
                    Circle().fill(Service.color(source)).frame(width: 8, height: 8)
                    Text(Service.label(source)).font(.caption)
                    Spacer()
                    Text("\(Int((seconds / max(total, 1) * 100).rounded()))%")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(formatDuration(seconds)).font(.caption.weight(.medium)).monospacedDigit()
                        .frame(minWidth: 54, alignment: .trailing)
                }
            }

            if !songs.isEmpty {
                Divider()
                Text("\(plays.count) \(plays.count == 1 ? "play" : "plays")")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(shown) { song in
                    PlayRow(entry: song.entry, artworkSize: 36) {
                        if song.count > 1 {
                            Text("\(song.count)×").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if songs.count > 5 {
                    Button(showAll ? "Show less" : "Show all \(songs.count)") { showAll.toggle() }
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: title) { _ in showAll = false }
    }

    /// Plays grouped by song, most played first.
    private static func songs(_ plays: [HistoryEntry]) -> [Song] {
        var map: [String: Song] = [:]
        for p in plays {
            let key = "\(p.source ?? "ios")|\(p.trackID)"
            map[key, default: Song(id: key, entry: p, count: 0)].count += 1
        }
        return map.values.sorted { ($0.count, $1.entry.title) > ($1.count, $0.entry.title) }
    }
}

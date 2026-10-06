import SwiftUI

// The share card, mirroring the extension's (popup.js): the same periods, chart,
// per-service split and all-time leaders, drawn at the same 4:5 proportions —
// 360×450 points rendered at 3× gives the extension's 1080×1350 pixels.

enum SharePeriod: String, CaseIterable, Identifiable {
    case day, week, month, year
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }

    var label: String {
        switch self {
        case .day: return "Today"
        case .week: return "This week"
        case .month: return "Past 30 days"
        case .year: return "Past 12 months"
        }
    }

    var caption: String {
        switch self {
        case .day: return "today"
        case .week: return "this week"
        case .month: return "in the past 30 days"
        case .year: return "in the past year"
        }
    }

    /// The first day the period covers. A period always ends today: a card that
    /// counted days still to come would read as a drop in listening.
    func start(today: Date, calendar cal: Calendar) -> Date {
        switch self {
        case .day:
            return today
        case .week:
            // Monday, as in the extension, whatever the phone's region says.
            let weekday = cal.component(.weekday, from: today) // 1 = Sunday
            return cal.date(byAdding: .day, value: -((weekday + 5) % 7), to: today) ?? today
        case .month:
            return cal.date(byAdding: .day, value: -29, to: today) ?? today
        case .year:
            // The last twelve calendar months, so the number and the twelve
            // columns beneath it are counting exactly the same days.
            return cal.date(byAdding: .month, value: -11, to: firstOfMonth(today, cal)) ?? today
        }
    }
}

private func firstOfMonth(_ date: Date, _ cal: Calendar) -> Date {
    cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
}

struct ShareColumn: Identifiable {
    let id: Int
    var services: [String: Double]
    var tick: String
    var seconds: Double { services.values.reduce(0, +) }
}

struct ShareService: Identifiable {
    let source: String
    let seconds: Double
    var percent = 0
    var id: String { source }
}

struct ShareData {
    let period: SharePeriod
    let seconds: Double
    let services: [ShareService]
    let columns: [ShareColumn]
    let track: TrackStat?
    let artist: String?
    let range: String

    @MainActor init(store: Store, period: SharePeriod) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = period.start(today: today, calendar: cal)
        let count = (cal.dateComponents([.day], from: start, to: today).day ?? 0) + 1
        let days = store.lastDays(count)

        var parts: [String: Double] = [:]
        for day in days { parts.merge(day.services, uniquingKeysWith: +) }
        let total = parts.values.reduce(0, +)

        self.period = period
        seconds = total
        services = Self.withPercentages(
            parts.filter { $0.value > 0 }
                .map { ShareService(source: $0.key, seconds: $0.value) }
                .sorted { $0.seconds > $1.seconds },
            total: total)
        columns = Self.makeColumns(days, period: period, today: today, calendar: cal)

        // Per-track and per-artist figures are running totals, not per day, so
        // the card names the all-time leaders and says as much on the label.
        track = store.allTracks.max { $0.seconds < $1.seconds }
        artist = store.artists.first?.name

        if count == 1 {
            range = today.formatted(.dateTime.day().month(.abbreviated).year())
        } else {
            // The year only when the range straddles new year, where "1 Nov – 3 Oct
            // 2026" would otherwise read as a gap of eleven months, not a year.
            let sameYear = cal.component(.year, from: start) == cal.component(.year, from: today)
            let from = sameYear
                ? start.formatted(.dateTime.day().month(.abbreviated))
                : start.formatted(.dateTime.day().month(.abbreviated).year())
            range = "\(from) – \(today.formatted(.dateTime.day().month(.abbreviated).year()))"
        }
    }

    var hasChart: Bool { columns.contains { $0.seconds > 0 } }

    var caption: String {
        guard seconds > 0 else {
            return "No music tracked \(period.caption) yet — counted by Music Counter."
        }
        let split = services.map { "\($0.percent)% \(Service.label($0.source))" }.joined(separator: ", ")
        return "🎧 \(formatDuration(seconds)) of music \(period.caption)\(split.isEmpty ? "" : " — \(split)"). Counted by Music Counter."
    }

    /// Day columns for the week and month, calendar-month columns for the year:
    /// twelve bars say "when in the year", 365 of them say nothing at all.
    private static func makeColumns(_ days: [DayListening], period: SharePeriod, today: Date, calendar cal: Calendar) -> [ShareColumn] {
        switch period {
        case .day:
            return []
        case .week, .month:
            return days.enumerated().map { i, day in
                let tick: String
                if period == .week {
                    tick = day.date.formatted(.dateTime.weekday(.narrow))
                } else {
                    tick = (days.count - 1 - i) % 5 == 0 ? day.date.formatted(.dateTime.day()) : ""
                }
                return ShareColumn(id: i, services: day.services, tick: tick)
            }
        case .year:
            let first = firstOfMonth(today, cal)
            var months = (0..<12).map { i -> (start: Date, column: ShareColumn) in
                let start = cal.date(byAdding: .month, value: i - 11, to: first) ?? first
                return (start, ShareColumn(id: i, services: [:], tick: start.formatted(.dateTime.month(.abbreviated))))
            }
            for day in days {
                guard let i = months.firstIndex(where: { cal.isDate($0.start, equalTo: day.date, toGranularity: .month) }) else { continue }
                months[i].column.services.merge(day.services, uniquingKeysWith: +)
            }
            return months.map(\.column)
        }
    }

    /// Rounding each share on its own gives cards reading 63% and 38%. Hand the
    /// rounding loss to the entries with most of it owing, so the figures add up.
    private static func withPercentages(_ services: [ShareService], total: Double) -> [ShareService] {
        guard total > 0 else { return services }
        let raw = services.map { $0.seconds / total * 100 }
        var out = services
        for i in out.indices { out[i].percent = Int(raw[i].rounded(.down)) }
        var left = 100 - out.reduce(0) { $0 + $1.percent }
        for i in raw.indices.sorted(by: { raw[$0].truncatingRemainder(dividingBy: 1) > raw[$1].truncatingRemainder(dividingBy: 1) }) {
            guard left > 0 else { break }
            out[i].percent += 1
            left -= 1
        }
        return out
    }
}

// MARK: - The card

private enum CardColor {
    static let bg = Color(red: 0x12 / 255, green: 0x10 / 255, blue: 0x1a / 255)
    static let panel = Color(red: 0x1b / 255, green: 0x18 / 255, blue: 0x26 / 255)
    static let text = Color(red: 0xf2 / 255, green: 0xee / 255, blue: 0xfb / 255)
    static let muted = Color(red: 0x9b / 255, green: 0x93 / 255, blue: 0xb3 / 255)
    static let axis = Color(red: 0x3a / 255, green: 0x33 / 255, blue: 0x50 / 255)
}

/// The picture behind the Share button.
struct ShareCardView: View {
    let data: ShareData

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("MUSIC COUNTER").font(.system(size: 9, weight: .bold)).tracking(2.3)
                Spacer()
                Text(data.range).font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(CardColor.muted)
            .padding(.top, 12)

            VStack(spacing: 4) {
                Text(data.period.label)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(CardColor.text)
                Text(data.seconds > 0 ? formatDuration(data.seconds) : "Nothing yet")
                    .font(.system(size: 49, weight: .bold)).foregroundStyle(Theme.gradient)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(data.seconds > 0 ? "of music listened" : "no music tracked yet")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(CardColor.muted)
            }
            .fixedSize(horizontal: false, vertical: true) // the chart gives way, not the number
            .padding(.top, 22)

            // The chart takes whatever room the blocks below leave it; with
            // nothing to plot they sit under the headline instead.
            if data.hasChart {
                ShareCardChart(columns: data.columns)
                    .frame(maxHeight: 80)
                    .padding(.top, 16)
                Spacer(minLength: 16)
            } else {
                Spacer().frame(height: 26)
            }

            VStack(spacing: 8) {
                if !data.services.isEmpty { services }
                if data.track != nil || data.artist != nil { leaders }
            }

            if !data.hasChart { Spacer(minLength: 0) }

            Text("Counted by Music Counter")
                .font(.system(size: 8, weight: .medium)).foregroundStyle(CardColor.muted)
                .padding(.top, 14)
        }
        .padding(28)
        .frame(width: 360, height: 450)
        .background {
            ZStack {
                CardColor.bg
                // A single wash of accent behind the headline, so the card does
                // not read as a flat screenshot of the app.
                RadialGradient(colors: [Theme.accent.opacity(0.2), .clear],
                               center: UnitPoint(x: 0.5, y: 0.22), startRadius: 0, endRadius: 270)
            }
        }
    }

    /// One bar split by service and a two-column legend under it: the same
    /// figures as the extension's row per service, in half the height, so four
    /// services still leave the chart room on a phone-sized card.
    private var services: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("BY SERVICE").font(.system(size: 7, weight: .bold)).tracking(2).foregroundStyle(CardColor.muted)
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(data.services) { service in
                        Service.color(service.source)
                            .frame(width: max((geo.size.width - 1.5 * CGFloat(data.services.count - 1)) * service.seconds / max(data.seconds, 1), 2))
                    }
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            // A plain Grid, not a lazy one: ImageRenderer draws lazy stacks blank.
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                ForEach(Array(stride(from: 0, to: data.services.count, by: 2)), id: \.self) { i in
                    GridRow {
                        legend(data.services[i])
                        if i + 1 < data.services.count { legend(data.services[i + 1]) } else { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                    }
                }
            }
        }
    }

    private func legend(_ service: ShareService) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Service.color(service.source)).frame(width: 5, height: 5)
            Text(Service.label(service.source))
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(CardColor.text)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            Text("\(formatDuration(service.seconds)) · \(service.percent)%")
                .font(.system(size: 8.5, weight: .medium)).foregroundStyle(CardColor.muted)
                .lineLimit(1).fixedSize()
        }
        .frame(maxWidth: .infinity)
    }

    private var leaders: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ALL TIME").font(.system(size: 7, weight: .bold)).tracking(2).foregroundStyle(CardColor.muted)
            if let track = data.track {
                leader("Most played", track.artist.isEmpty ? track.title : "\(track.title) — \(track.artist)")
            }
            if let artist = data.artist { leader("Top artist", artist) }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardColor.panel, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func leader(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(CardColor.muted)
            Text(value).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(CardColor.text).lineLimit(1)
        }
    }
}

private struct ShareCardChart: View {
    let columns: [ShareColumn]

    var body: some View {
        let top = columns.map(\.seconds).max() ?? 0
        let gap: CGFloat = columns.count > 20 ? 1.3 : 3.3
        VStack(spacing: 5) {
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(columns) { column in
                        bar(column, height: top > 0 ? max(geo.size.height * column.seconds / top, column.seconds > 0 ? 1.5 : 0) : 0)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            Rectangle().fill(CardColor.axis).frame(height: 0.7)
            HStack(spacing: gap) {
                ForEach(columns) { column in
                    // Every tick gets its column's width; a longer month name is
                    // squeezed to fit rather than spilling onto its neighbour.
                    Text(column.tick)
                        .font(.system(size: 7, weight: .medium)).foregroundStyle(CardColor.muted)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// A column stacked by service in the chart's order, first service at the foot.
    private func bar(_ column: ShareColumn, height: CGFloat) -> some View {
        let parts = Service.ordered(column.services)
        let total = max(column.seconds, 1)
        return VStack(spacing: 0) {
            ForEach(parts.reversed(), id: \.key) { part in
                Service.color(part.key).frame(height: height * part.value / total)
            }
        }
        .frame(height: height)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2.7, topTrailingRadius: 2.7, style: .continuous))
    }
}

// MARK: - The sheet

struct ShareSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var period = SharePeriod.week
    @State private var image: Image?

    var body: some View {
        let data = ShareData(store: store, period: period)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Period", selection: $period) {
                        ForEach(SharePeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Group {
                        if let image {
                            image.resizable().aspectRatio(4 / 5, contentMode: .fit)
                        } else {
                            Color.clear.aspectRatio(4 / 5, contentMode: .fit)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)

                    Text(data.caption)
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let image {
                        ShareLink(item: image, subject: Text("My listening"), message: Text(data.caption),
                                  preview: SharePreview("My listening", image: image)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Share your listening")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            // An open card is a picture of these very numbers; keep it in step.
            .task(id: "\(period.rawValue) \(store.totalSeconds)") { render(data) }
        }
    }

    private func render(_ data: ShareData) {
        let renderer = ImageRenderer(content: ShareCardView(data: data).environment(\.colorScheme, .dark))
        renderer.scale = 3
        if let ui = renderer.uiImage { image = Image(uiImage: ui) }
    }
}

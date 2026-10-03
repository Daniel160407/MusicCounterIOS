import SwiftUI
import Charts

struct InsightsView: View {
    @EnvironmentObject var store: Store
    @State private var rangeDays = 7
    @State private var daysAgo = 0
    @State private var allTime = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    daysCard
                    hoursCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Insights")
        }
    }

    private var daysCard: some View {
        let days = store.lastDays(rangeDays)
        let total = days.reduce(0) { $0 + $1.seconds }
        let active = days.filter { $0.seconds >= 1 }.count
        return Card(title: "Days you listened") {
            Picker("Range", selection: $rangeDays) {
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
            }
            .pickerStyle(.segmented)

            DaysChart(days: days).frame(height: 170)

            HStack {
                Text("Total \(formatDuration(total))")
                Spacer()
                Text("Active \(active)/\(rangeDays) days")
                Spacer()
                Text("Avg \(formatDuration(total / Double(max(rangeDays, 1))))/day")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var hoursCard: some View {
        let hours = allTime ? store.allTimeHours : store.hours(daysAgo: daysAgo)
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

            Chart(Array(hours.enumerated()), id: \.offset) { hour, seconds in
                BarMark(
                    x: .value("Hour", hour),
                    y: .value("Minutes", seconds / 60)
                )
                .cornerRadius(3)
                .foregroundStyle(hour == peak?.offset && seconds > 0
                                 ? AnyShapeStyle(Theme.gradient)
                                 : AnyShapeStyle(Theme.accent.opacity(0.35)))
            }
            .chartXScale(domain: -0.5...23.5)
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

            if let peak, peak.element > 0 {
                Text("Busiest hour: \(String(format: "%02d", peak.offset)):00 · \(formatDuration(peak.element))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Nothing recorded for this period.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

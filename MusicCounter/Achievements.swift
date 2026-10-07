import AudioToolbox
import Foundation
import Combine
import UIKit
import UserNotifications

/// One badge. The browser extension carries the same list in achievements.js —
/// keep ids, goals and wording in step, so both apps award the same badges from
/// the same synced numbers.
struct Achievement: Identifiable {
    enum Metric {
        case totalSeconds, bestDaySeconds, nightOwl, earlyBird, longestStreak, activeDays
        case bestWeekendSeconds, bestWeekSeconds, activeWeeks, bestDayServices, pocketSeconds, dawnToDusk, hoursCovered, longestHabit, longestGap, daysSinceFirst
        case totalPlays, topTrackPlays, bestDayPlays, artistCount, trackCount, topArtistSeconds, serviceCount, favoriteCount
        // The day, week and weekend you're in now.
        case todaySeconds, todayPlays, todayServices, thisWeekSeconds, thisWeekendSeconds

        /// Badges won within one day, week or weekend are earned by your best one,
        /// but while locked they show how the current one is going: the metric
        /// measuring the period you're in, and the word that names it.
        var current: (metric: Metric, period: String)? {
            switch self {
            case .bestDaySeconds: (.todaySeconds, "today")
            case .bestDayPlays: (.todayPlays, "today")
            case .bestDayServices: (.todayServices, "today")
            case .bestWeekSeconds: (.thisWeekSeconds, "this week")
            case .bestWeekendSeconds: (.thisWeekendSeconds, "this weekend")
            default: nil
            }
        }
    }

    enum Unit { case time, days, weeks, count, flag }

    let id: String
    let group: String
    let symbol: String
    let title: String
    let text: String
    let metric: Metric
    let goal: Double
    let unit: Unit

    private static let hour = 3600.0

    static let all: [Achievement] = [
        // Listening time
        .init(id: "first-note", group: "Time", symbol: "music.note", title: "First Note", text: "Listen for your first minute", metric: .totalSeconds, goal: 60, unit: .time),
        .init(id: "warming-up", group: "Time", symbol: "flame.fill", title: "Warming Up", text: "Listen for 1 hour in total", metric: .totalSeconds, goal: hour, unit: .time),
        .init(id: "dedicated", group: "Time", symbol: "headphones", title: "Dedicated Listener", text: "Listen for 10 hours in total", metric: .totalSeconds, goal: 10 * hour, unit: .time),
        .init(id: "audiophile", group: "Time", symbol: "opticaldisc.fill", title: "Audiophile", text: "Listen for 100 hours in total", metric: .totalSeconds, goal: 100 * hour, unit: .time),
        .init(id: "soundtrack", group: "Time", symbol: "trophy.fill", title: "Living Soundtrack", text: "Listen for 500 hours in total", metric: .totalSeconds, goal: 500 * hour, unit: .time),
        .init(id: "lifetime", group: "Time", symbol: "crown.fill", title: "Lifetime Listener", text: "Listen for 1,000 hours in total", metric: .totalSeconds, goal: 1000 * hour, unit: .time),

        // One day
        .init(id: "deep-session", group: "Sessions", symbol: "water.waves", title: "Deep Session", text: "Listen for 2 hours in one day", metric: .bestDaySeconds, goal: 2 * hour, unit: .time),
        .init(id: "marathon", group: "Sessions", symbol: "figure.run", title: "Marathon", text: "Listen for 6 hours in one day", metric: .bestDaySeconds, goal: 6 * hour, unit: .time),
        .init(id: "all-nighter", group: "Sessions", symbol: "moon.fill", title: "All-Nighter", text: "Listen for 10 hours in one day", metric: .bestDaySeconds, goal: 10 * hour, unit: .time),
        .init(id: "weekend-warrior", group: "Sessions", symbol: "party.popper.fill", title: "Weekend Warrior", text: "Listen for 5 hours over one Saturday and Sunday", metric: .bestWeekendSeconds, goal: 5 * hour, unit: .time),
        .init(id: "big-week", group: "Sessions", symbol: "calendar", title: "Big Week", text: "Listen for 20 hours in one week", metric: .bestWeekSeconds, goal: 20 * hour, unit: .time),
        .init(id: "night-owl", group: "Sessions", symbol: "moon.stars.fill", title: "Night Owl", text: "Listen for 10 minutes between midnight and 4 AM", metric: .nightOwl, goal: 1, unit: .flag),
        .init(id: "early-bird", group: "Sessions", symbol: "sunrise.fill", title: "Early Bird", text: "Listen for 10 minutes between 5 and 7 AM", metric: .earlyBird, goal: 1, unit: .flag),
        .init(id: "dawn-to-dusk", group: "Sessions", symbol: "sun.horizon.fill", title: "Dawn to Dusk", text: "Listen for 10 minutes in the night, morning, afternoon and evening of one day", metric: .dawnToDusk, goal: 1, unit: .flag),
        .init(id: "around-the-clock", group: "Sessions", symbol: "clock.fill", title: "Around the Clock", text: "Listen in every one of the 24 hours of the day", metric: .hoursCovered, goal: 24, unit: .count),

        // Habits
        .init(id: "streak-3", group: "Streaks", symbol: "sparkles", title: "On a Roll", text: "Listen 3 days in a row", metric: .longestStreak, goal: 3, unit: .days),
        .init(id: "streak-7", group: "Streaks", symbol: "calendar", title: "Week Strong", text: "Listen 7 days in a row", metric: .longestStreak, goal: 7, unit: .days),
        .init(id: "streak-30", group: "Streaks", symbol: "calendar.badge.checkmark", title: "Monthly Ritual", text: "Listen 30 days in a row", metric: .longestStreak, goal: 30, unit: .days),
        .init(id: "streak-100", group: "Streaks", symbol: "bolt.fill", title: "Unbreakable", text: "Listen 100 days in a row", metric: .longestStreak, goal: 100, unit: .days),
        .init(id: "streak-365", group: "Streaks", symbol: "sun.max.fill", title: "Year of Music", text: "Listen 365 days in a row", metric: .longestStreak, goal: 365, unit: .days),
        .init(id: "daily-habit", group: "Streaks", symbol: "alarm.fill", title: "Daily Habit", text: "Listen for 30 minutes a day, 7 days in a row", metric: .longestHabit, goal: 7, unit: .days),
        .init(id: "regular", group: "Streaks", symbol: "chart.line.uptrend.xyaxis", title: "Regular", text: "Listen on 30 different days", metric: .activeDays, goal: 30, unit: .days),
        .init(id: "devoted", group: "Streaks", symbol: "hands.clap.fill", title: "Devoted", text: "Listen on 100 different days", metric: .activeDays, goal: 100, unit: .days),
        .init(id: "weekly-ritual", group: "Streaks", symbol: "calendar.badge.checkmark", title: "Weekly Ritual", text: "Listen in 52 different weeks", metric: .activeWeeks, goal: 52, unit: .weeks),

        // Plays
        .init(id: "century", group: "Plays", symbol: "play.fill", title: "Century", text: "Play 100 tracks", metric: .totalPlays, goal: 100, unit: .count),
        .init(id: "thousand", group: "Plays", symbol: "play.square.stack.fill", title: "Thousand Plays", text: "Play 1,000 tracks", metric: .totalPlays, goal: 1000, unit: .count),
        .init(id: "jukebox", group: "Plays", symbol: "radio.fill", title: "Jukebox", text: "Play 5,000 tracks", metric: .totalPlays, goal: 5000, unit: .count),
        .init(id: "on-repeat", group: "Plays", symbol: "repeat", title: "On Repeat", text: "Play the same track 10 times", metric: .topTrackPlays, goal: 10, unit: .count),
        .init(id: "obsessed", group: "Plays", symbol: "repeat.1", title: "Obsessed", text: "Play the same track 50 times", metric: .topTrackPlays, goal: 50, unit: .count),
        .init(id: "broken-record", group: "Plays", symbol: "record.circle.fill", title: "Broken Record", text: "Play the same track 100 times", metric: .topTrackPlays, goal: 100, unit: .count),
        .init(id: "day-plays-50", group: "Plays", symbol: "music.note.list", title: "Full Rotation", text: "Play 50 tracks in one day", metric: .bestDayPlays, goal: 50, unit: .count),
        .init(id: "day-plays-100", group: "Plays", symbol: "star.circle.fill", title: "Hundred Club", text: "Play 100 tracks in one day", metric: .bestDayPlays, goal: 100, unit: .count),
        .init(id: "day-plays-300", group: "Plays", symbol: "bolt.fill", title: "Track Frenzy", text: "Play 300 tracks in one day", metric: .bestDayPlays, goal: 300, unit: .count),
        .init(id: "day-plays-500", group: "Plays", symbol: "infinity", title: "Endless Mix", text: "Play 500 tracks in one day", metric: .bestDayPlays, goal: 500, unit: .count),

        // Variety
        .init(id: "explorer", group: "Variety", symbol: "safari.fill", title: "Explorer", text: "Listen to 10 different artists", metric: .artistCount, goal: 10, unit: .count),
        .init(id: "globetrotter", group: "Variety", symbol: "globe.europe.africa.fill", title: "Globetrotter", text: "Listen to 50 different artists", metric: .artistCount, goal: 50, unit: .count),
        .init(id: "crate-digger", group: "Variety", symbol: "shippingbox.fill", title: "Crate Digger", text: "Listen to 200 different artists", metric: .artistCount, goal: 200, unit: .count),
        .init(id: "encyclopedia", group: "Variety", symbol: "books.vertical.fill", title: "Encyclopedia", text: "Listen to 500 different artists", metric: .artistCount, goal: 500, unit: .count),
        .init(id: "variety-pack", group: "Variety", symbol: "paintpalette.fill", title: "Variety Pack", text: "Listen to 100 different tracks", metric: .trackCount, goal: 100, unit: .count),
        .init(id: "deep-catalog", group: "Variety", symbol: "square.stack.3d.up.fill", title: "Deep Catalog", text: "Listen to 500 different tracks", metric: .trackCount, goal: 500, unit: .count),
        .init(id: "superfan", group: "Variety", symbol: "person.fill.checkmark", title: "Superfan", text: "Spend 10 hours with one artist", metric: .topArtistSeconds, goal: 10 * hour, unit: .time),
        .init(id: "ultimate-fan", group: "Variety", symbol: "heart.fill", title: "Ultimate Fan", text: "Spend 50 hours with one artist", metric: .topArtistSeconds, goal: 50 * hour, unit: .time),
        .init(id: "everywhere", group: "Variety", symbol: "antenna.radiowaves.left.and.right", title: "Everywhere", text: "Listen on 3 different services", metric: .serviceCount, goal: 3, unit: .count),
        .init(id: "switch-hitter", group: "Variety", symbol: "shuffle", title: "Switch Hitter", text: "Listen on 3 services in one day", metric: .bestDayServices, goal: 3, unit: .count),
        .init(id: "pocket-rocket", group: "Variety", symbol: "iphone.gen3", title: "Pocket Rocket", text: "Listen for 50 hours on Pocket", metric: .pocketSeconds, goal: 50 * hour, unit: .time),

        // Favorites
        .init(id: "first-love", group: "Favorites", symbol: "star.fill", title: "First Love", text: "Star your first favorite", metric: .favoriteCount, goal: 1, unit: .count),
        .init(id: "collector", group: "Favorites", symbol: "diamond.fill", title: "Collector", text: "Star 25 favorites", metric: .favoriteCount, goal: 25, unit: .count),
        .init(id: "curator", group: "Favorites", symbol: "rectangle.stack.fill", title: "Curator", text: "Star 100 favorites", metric: .favoriteCount, goal: 100, unit: .count),

        // Milestones
        .init(id: "one-month", group: "Milestones", symbol: "leaf.fill", title: "One Month In", text: "Keep counting for 30 days since your first listen", metric: .daysSinceFirst, goal: 30, unit: .days),
        .init(id: "one-year", group: "Milestones", symbol: "birthday.cake.fill", title: "One Year Together", text: "Keep counting for a year since your first listen", metric: .daysSinceFirst, goal: 365, unit: .days),
        .init(id: "welcome-back", group: "Milestones", symbol: "hand.wave.fill", title: "Welcome Back", text: "Come back to music after 30 days away", metric: .longestGap, goal: AchievementMetrics.comebackGapDays, unit: .flag),
    ]

    static let groups = ["Time", "Sessions", "Streaks", "Plays", "Variety", "Favorites", "Milestones"]
}

/// An achievement with where you stand on it.
struct AchievementStatus: Identifiable {
    let achievement: Achievement
    /// Capped at the goal.
    let value: Double
    let unlockedAt: Date?
    var id: String { achievement.id }
    var progress: Double { min(value / achievement.goal, 1) }

    var progressText: String {
        let a = achievement
        // A badge won within one day, week or weekend shows the one you're in.
        let period = a.metric.current.map { " \($0.period)" } ?? ""
        switch a.unit {
        case .flag: return ""
        case .time: return "\(formatDuration(value)) / \(formatDuration(a.goal))\(period)"
        case .days: return "\(Int(value)) / \(Int(a.goal)) days\(period)"
        case .weeks: return "\(Int(value)) / \(Int(a.goal)) weeks\(period)"
        case .count: return "\(Int(value).formatted()) / \(Int(a.goal).formatted())\(period)"
        }
    }
}

enum AchievementMetrics {
    /// A day only counts towards streaks and active days with at least this much.
    static let activeDaySeconds = 60.0
    /// A late-night or early-morning hour needs this much listening to count.
    static let sessionHourSeconds = 600.0
    /// Each part of the day needs this much for Dawn to Dusk.
    static let dayPartSeconds = 600.0
    /// A day only counts towards Daily Habit with at least this much.
    static let habitDaySeconds = 1800.0
    /// Days with no listening at all between two listening days, for Welcome Back.
    static let comebackGapDays = 30.0

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    @MainActor
    static func measure(_ store: Store) -> [Achievement.Metric: Double] {
        let days = store.allDayTotals
        let active = days.filter { $0.value >= activeDaySeconds }.map(\.key)

        var nightOwl = 0.0, earlyBird = 0.0, dawnToDusk = 0.0
        var hourTotals = Array(repeating: 0.0, count: 24)
        for hours in store.allDayHours {
            // Night 0–6, morning 6–12, afternoon 12–18, evening 18–24.
            var parts = [0.0, 0.0, 0.0, 0.0]
            for (h, seconds) in hours.enumerated() where h < 24 {
                hourTotals[h] += seconds
                parts[h / 6] += seconds
                guard seconds >= sessionHourSeconds else { continue }
                if h < 4 { nightOwl = 1 }
                if h == 5 || h == 6 { earlyBird = 1 }
            }
            if parts.allSatisfy({ $0 >= dayPartSeconds }) { dawnToDusk = 1 }
        }

        // A weekend is a Saturday plus the Sunday after it; a Sunday on its own counts too.
        let cal = Calendar.current
        var bestWeekend = 0.0
        for (key, seconds) in days {
            guard let date = dayFormatter.date(from: key) else { continue }
            switch cal.component(.weekday, from: date) {
            case 7:
                let sunday = cal.date(byAdding: .day, value: 1, to: date).map { dayFormatter.string(from: $0) }
                bestWeekend = max(bestWeekend, seconds + (sunday.flatMap { days[$0] } ?? 0))
            case 1:
                bestWeekend = max(bestWeekend, seconds)
            default:
                break
            }
        }

        // Weeks run Monday to Sunday.
        var weekTotals: [String: Double] = [:]
        for (key, seconds) in days {
            guard let week = weekKey(key) else { continue }
            weekTotals[week, default: 0] += seconds
        }
        let activeWeeks = Set(active.compactMap(weekKey)).count

        var bestDayServices = 0
        for hours in store.allDayHourServices.values {
            var services: [String: Double] = [:]
            for slice in hours.prefix(24) {
                for (source, seconds) in slice where source != Service.other && seconds > 0 {
                    services[source, default: 0] += seconds
                }
            }
            bestDayServices = max(bestDayServices, services.values.filter { $0 >= activeDaySeconds }.count)
        }

        // Plays per day come from the history, one row per play, so a day the
        // retention setting has trimmed away no longer counts.
        var dayPlays: [String: Int] = [:]
        for e in store.allHistory { dayPlays[dayFormatter.string(from: e.at), default: 0] += 1 }

        // The day, week and weekend you're in now. On a weekday the weekend is the
        // coming one, so nothing has been listened to in it yet.
        let today = cal.startOfDay(for: Date())
        let todayKey = dayFormatter.string(from: today)
        var todayServiceSeconds: [String: Double] = [:]
        for slice in (store.allDayHourServices[todayKey] ?? []).prefix(24) {
            for (source, seconds) in slice where source != Service.other && seconds > 0 {
                todayServiceSeconds[source, default: 0] += seconds
            }
        }
        func dayTotal(_ offset: Int) -> Double {
            cal.date(byAdding: .day, value: offset, to: today).flatMap { days[dayFormatter.string(from: $0)] } ?? 0
        }
        let thisWeekend: Double = switch cal.component(.weekday, from: today) {
        case 7: dayTotal(0)
        case 1: dayTotal(-1) + dayTotal(0)
        default: 0
        }

        let activeRuns = runs(active)
        let habit = days.filter { $0.value >= habitDaySeconds }.map(\.key)
        let daysSinceFirst = activeRuns.first.flatMap {
            cal.dateComponents([.day], from: $0, to: cal.startOfDay(for: Date())).day
        } ?? 0

        let tracks = store.allTracks
        let artists = store.artists.filter { !ArtistName.isUnknown($0.name) && $0.seconds >= 1 }

        return [
            .totalSeconds: store.totalSeconds,
            .bestDaySeconds: days.values.max() ?? 0,
            .nightOwl: nightOwl,
            .earlyBird: earlyBird,
            .bestWeekendSeconds: bestWeekend,
            .bestWeekSeconds: weekTotals.values.max() ?? 0,
            .todaySeconds: days[todayKey] ?? 0,
            .todayPlays: Double(dayPlays[todayKey] ?? 0),
            .todayServices: Double(todayServiceSeconds.values.filter { $0 >= activeDaySeconds }.count),
            .thisWeekSeconds: weekKey(todayKey).flatMap { weekTotals[$0] } ?? 0,
            .thisWeekendSeconds: thisWeekend,
            .activeWeeks: Double(activeWeeks),
            .bestDayServices: Double(bestDayServices),
            .pocketSeconds: store.services.first { $0.source == "ios" }?.seconds ?? 0,
            .dawnToDusk: dawnToDusk,
            .hoursCovered: Double(hourTotals.filter { $0 >= activeDaySeconds }.count),
            .longestStreak: Double(activeRuns.longest),
            .longestHabit: Double(runs(habit).longest),
            .activeDays: Double(active.count),
            .longestGap: Double(activeRuns.longestGap),
            .daysSinceFirst: Double(daysSinceFirst),
            .totalPlays: Double(store.totalPlays),
            .topTrackPlays: Double(tracks.map(\.plays).max() ?? 0),
            .bestDayPlays: Double(dayPlays.values.max() ?? 0),
            .artistCount: Double(artists.count),
            .trackCount: Double(tracks.filter { $0.seconds >= 1 || $0.plays > 0 }.count),
            .topArtistSeconds: artists.first?.seconds ?? 0,
            .serviceCount: Double(store.services.filter { $0.source != Service.other && $0.seconds >= activeDaySeconds }.count),
            .favoriteCount: Double(store.stats.favorites.count),
        ]
    }

    /// When each badge was really earned, replayed from the hour-by-hour listening,
    /// the play history and the favourites. Badges can be earned from listening that
    /// happened before they existed, or that arrives late from another device, so the
    /// moment the app notices isn't always the moment it was earned. An hour's
    /// listening is taken as spread evenly across it, which places a time to within
    /// the hour. Per-artist time has no timeline, so Superfan and Ultimate Fan can't
    /// be dated. Mirrors replayUnlockTimes in the extension's achievements.js.
    @MainActor
    static func replayUnlockTimes(_ store: Store) -> [String: Date] {
        let byMetric = Dictionary(grouping: Achievement.all, by: \.metric)
        let now = Date()
        var found: [String: Date] = [:]
        func reach(_ metric: Achievement.Metric, _ value: Double, _ at: Date) {
            for a in byMetric[metric] ?? [] where found[a.id] == nil && value >= a.goal && at <= now {
                found[a.id] = at
            }
        }

        let cal = Calendar.current
        struct Slice { let key: String; let day: Date; let hour: Int; let start: Date; let services: [String: Double]; let total: Double }
        var slices: [Slice] = []
        for (key, hours) in store.allDayHourServices {
            guard let day = dayFormatter.date(from: key).map({ cal.startOfDay(for: $0) }) else { continue }
            for (h, services) in hours.enumerated() where h < 24 {
                let total = services.values.reduce(0, +)
                guard total > 0, let start = cal.date(bySettingHour: h, minute: 0, second: 0, of: day) else { continue }
                slices.append(Slice(key: key, day: day, hour: h, start: start, services: services, total: total))
            }
        }
        slices.sort { $0.start < $1.start }

        struct Run { var last: Date?; var first: Date?; var length = 0, longest = 0, gap = 0, count = 0 }
        func extend(_ run: inout Run, _ day: Date) {
            let step = run.last.flatMap { cal.dateComponents([.day], from: $0, to: day).day } ?? 0
            run.length = run.last != nil && step == 1 ? run.length + 1 : 1
            run.longest = max(run.longest, run.length)
            if run.last != nil { run.gap = max(run.gap, step - 1) }
            run.count += 1
            if run.first == nil { run.first = day }
            run.last = day
        }

        let steps = 60
        var total = 0.0
        var dayTotals: [String: Double] = [:]
        var weekendTotals: [String: Double] = [:]
        var weekTotals: [String: Double] = [:]
        var activeWeeks: Set<String> = []
        var dayServices: [String: [String: Double]] = [:]
        var dayParts: [String: [Double]] = [:]
        var hourTotals = Array(repeating: 0.0, count: 24)
        var sources: [String: Double] = [:]
        var active = Run(), habit = Run()

        for slice in slices {
            let key = slice.key, h = slice.hour
            // A Sunday adds to its Saturday's weekend.
            let weekend: String? = switch cal.component(.weekday, from: slice.day) {
            case 7: key
            case 1: cal.date(byAdding: .day, value: -1, to: slice.day).map { dayFormatter.string(from: $0) }
            default: nil
            }
            let week = weekKey(key)
            let known = slice.services.filter { $0.key != Service.other && $0.value > 0 }
            let shares = slice.services.filter { $0.value > 0 }.mapValues { $0 / slice.total }
            let step = slice.total / Double(steps)
            var hourSeconds = 0.0
            for i in 1...steps {
                let at = slice.start.addingTimeInterval(3600 * Double(i) / Double(steps))

                total += step
                reach(.totalSeconds, total, at)

                let before = dayTotals[key] ?? 0
                let today = before + step
                dayTotals[key] = today
                reach(.bestDaySeconds, today, at)
                if before < activeDaySeconds, today >= activeDaySeconds {
                    extend(&active, slice.day)
                    reach(.longestStreak, Double(active.longest), at)
                    reach(.activeDays, Double(active.count), at)
                    reach(.longestGap, Double(active.gap), at)
                    if let week { activeWeeks.insert(week) }
                    reach(.activeWeeks, Double(activeWeeks.count), at)
                }
                if before < habitDaySeconds, today >= habitDaySeconds {
                    extend(&habit, slice.day)
                    reach(.longestHabit, Double(habit.longest), at)
                }

                if let week {
                    weekTotals[week, default: 0] += step
                    reach(.bestWeekSeconds, weekTotals[week] ?? 0, at)
                }

                if let weekend {
                    weekendTotals[weekend, default: 0] += step
                    reach(.bestWeekendSeconds, weekendTotals[weekend] ?? 0, at)
                }

                hourSeconds += step
                if hourSeconds >= sessionHourSeconds {
                    if h < 4 { reach(.nightOwl, 1, at) }
                    if h == 5 || h == 6 { reach(.earlyBird, 1, at) }
                }

                var parts = dayParts[key] ?? [0, 0, 0, 0]
                parts[h / 6] += step
                dayParts[key] = parts
                if parts.allSatisfy({ $0 >= dayPartSeconds }) { reach(.dawnToDusk, 1, at) }

                hourTotals[h] += step
                reach(.hoursCovered, Double(hourTotals.filter { $0 >= activeDaySeconds }.count), at)

                for (source, share) in shares { sources[source, default: 0] += step * share }
                reach(.serviceCount, Double(sources.filter { $0.key != Service.other && $0.value >= activeDaySeconds }.count), at)
                reach(.pocketSeconds, sources["ios"] ?? 0, at)

                var servicesToday = dayServices[key] ?? [:]
                for (source, seconds) in known { servicesToday[source, default: 0] += seconds / Double(steps) }
                dayServices[key] = servicesToday
                reach(.bestDayServices, Double(servicesToday.values.filter { $0 >= activeDaySeconds }.count), at)
            }
        }

        if let first = active.first {
            for a in byMetric[.daysSinceFirst] ?? [] where found[a.id] == nil {
                if let when = cal.date(byAdding: .day, value: Int(a.goal), to: first), when <= now { found[a.id] = when }
            }
        }

        // History logs a play a little before it counts, so when it has more rows
        // than there are plays, the nth play is taken as the matching share of the
        // way through it. A shorter history lost its oldest rows to retention.
        let plays = store.allHistory.sorted { $0.at < $1.at }
        let totalPlays = store.totalPlays
        for a in byMetric[.totalPlays] ?? [] where totalPlays >= Int(a.goal) && !plays.isEmpty {
            let goal = Int(a.goal)
            let index = plays.count >= totalPlays
                ? Int((Double(goal * plays.count) / Double(totalPlays)).rounded(.up)) - 1
                : goal - 1 - (totalPlays - plays.count)
            if plays.indices.contains(index) { found[a.id] = plays[index].at }
        }
        var trackPlays: [String: Int] = [:]
        var artists = Set<String>()
        var dayPlays: [String: Int] = [:]
        for e in plays {
            let day = dayFormatter.string(from: e.at)
            dayPlays[day, default: 0] += 1
            reach(.bestDayPlays, Double(dayPlays[day] ?? 0), e.at)
            trackPlays[e.trackID, default: 0] += 1
            reach(.topTrackPlays, Double(trackPlays[e.trackID] ?? 0), e.at)
            reach(.trackCount, Double(trackPlays.count), e.at)
            if !ArtistName.isUnknown(e.artist) { artists.insert(e.artist) }
            reach(.artistCount, Double(artists.count), e.at)
        }

        for (i, at) in store.stats.favorites.values.map(\.addedAt).sorted().enumerated() {
            reach(.favoriteCount, Double(i + 1), at)
        }
        return found
    }

    /// The Monday that starts the week holding the day `key`, as a day key.
    static func weekKey(_ key: String) -> String? {
        let cal = Calendar.current
        guard let date = dayFormatter.date(from: key) else { return nil }
        let back = (cal.component(.weekday, from: date) + 5) % 7
        return cal.date(byAdding: .day, value: -back, to: date).map { dayFormatter.string(from: $0) }
    }

    /// Longest run of consecutive calendar days, and the longest stretch with none,
    /// among `keys` ("yyyy-MM-dd").
    static func runs(_ keys: [String]) -> (longest: Int, longestGap: Int, first: Date?) {
        let cal = Calendar.current
        let dates = keys.compactMap { dayFormatter.date(from: $0) }.map { cal.startOfDay(for: $0) }.sorted()
        var longest = 0, longestGap = 0, run = 0
        var prev: Date?
        for date in dates {
            let step = prev.flatMap { cal.dateComponents([.day], from: $0, to: date).day } ?? 0
            run = prev != nil && step == 1 ? run + 1 : 1
            longest = max(longest, run)
            if prev != nil { longestGap = max(longestGap, step - 1) }
            prev = date
        }
        return (longest, longestGap, dates.first)
    }
}

/// Keeps track of which badges have been earned and when. Earned badges stay
/// earned after a reset, the same as in the extension.
@MainActor
final class Achievements: ObservableObject {
    @Published private(set) var statuses: [AchievementStatus] = []
    /// Earned while the app was open; shown as a banner, then cleared.
    @Published var justUnlocked: [Achievement] = []
    /// Earned since the achievements page was last opened.
    @Published private(set) var unseen: Set<String>

    private static let unlockedKey = "achievementsUnlocked"
    private static let unseenKey = "achievementsUnseen"
    private static let datedKey = "achievementsDated"

    private var unlocked: [String: Date]
    /// Whether the badges have been dated from the listening yet (see `redate`).
    private var dated: Bool
    /// Whether they've been dated with other devices' listening loaded, this launch.
    private var datedWithRemote = false
    private let store: Store
    private var cancellable: AnyCancellable?

    init(store: Store) {
        self.store = store
        let raw = UserDefaults.standard.dictionary(forKey: Self.unlockedKey) as? [String: Double] ?? [:]
        unlocked = raw.mapValues { Date(timeIntervalSince1970: $0) }
        // Badges since retired can't be shown, so they mustn't count as unseen.
        unseen = Set(UserDefaults.standard.stringArray(forKey: Self.unseenKey) ?? [])
            .intersection(Achievement.all.map(\.id))
        dated = UserDefaults.standard.bool(forKey: Self.datedKey)
        // objectWillChange fires before the change lands; the debounce both lets it
        // land and keeps a burst of ticks down to one evaluation.
        cancellable = store.objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.evaluate() }
        evaluate(announce: false)
    }

    var earnedCount: Int { statuses.filter { $0.unlockedAt != nil }.count }

    /// Returns the badges earned by this call.
    @discardableResult
    func evaluate(announce: Bool = true) -> [Achievement] {
        let metrics = AchievementMetrics.measure(store)
        var fresh: [Achievement] = []
        for a in Achievement.all where unlocked[a.id] == nil && (metrics[a.metric] ?? 0) >= a.goal {
            unlocked[a.id] = Date()
            fresh.append(a)
        }
        let redating = !fresh.isEmpty || !dated || (store.hasRemote && !datedWithRemote)
        if redating { redate() }
        statuses = Achievement.all.map { a in
            let shown = a.metric.current?.metric ?? a.metric
            return AchievementStatus(achievement: a, value: min(metrics[shown] ?? 0, a.goal), unlockedAt: unlocked[a.id])
        }
        if redating { save() }
        guard !fresh.isEmpty else { return [] }
        unseen.formUnion(fresh.map(\.id))
        save()
        if announce {
            // On screen the in-app banner shows it; otherwise the system notification is all you'd see.
            if UIApplication.shared.applicationState == .active {
                justUnlocked.append(contentsOf: fresh)
                AchievementNotifier.shared.playChime()
            }
            Task { await AchievementNotifier.shared.post(fresh) }
        }
        return fresh
    }

    func markSeen() {
        guard !unseen.isEmpty else { return }
        unseen = []
        save()
    }

    /// New badges, and once the badges that predate this, are dated from when the
    /// listening actually reached them — again once other devices' listening has
    /// loaded. Only ever moves a date earlier, so a badge kept through a reset holds
    /// on to its original date.
    private func redate() {
        for (id, at) in AchievementMetrics.replayUnlockTimes(store) {
            if let current = unlocked[id], at < current { unlocked[id] = at }
        }
        dated = true
        if store.hasRemote { datedWithRemote = true }
    }

    private func save() {
        UserDefaults.standard.set(unlocked.mapValues { $0.timeIntervalSince1970 }, forKey: Self.unlockedKey)
        UserDefaults.standard.set(Array(unseen), forKey: Self.unseenKey)
        UserDefaults.standard.set(dated, forKey: Self.datedKey)
    }
}

/// Posts a local notification for each badge earned.
final class AchievementNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AchievementNotifier()

    /// The same chime the browser extension plays (its sounds/achievement.wav).
    static let soundFile = "achievement.wav"

    private lazy var chime: SystemSoundID? = {
        guard let url = Bundle.main.url(forResource: Self.soundFile, withExtension: nil) else { return nil }
        var id: SystemSoundID = 0
        return AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError ? id : nil
    }()

    /// Played with the app on screen, where the notification stays silent. A system
    /// sound mixes over whatever is playing and respects the silent switch.
    func playChime() {
        if let chime { AudioServicesPlaySystemSound(chime) }
    }

    /// Call once at launch: becomes the delegate and asks for permission (iOS only prompts the first time).
    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ achievements: [Achievement]) async {
        let center = UNUserNotificationCenter.current()
        for a in achievements {
            let content = UNMutableNotificationContent()
            content.title = "Achievement unlocked: \(a.title)"
            content.body = a.text
            content.sound = UNNotificationSound(named: UNNotificationSoundName(AchievementNotifier.soundFile))
            content.threadIdentifier = "achievements"
            // Keyed by achievement, so a badge can never be announced twice.
            try? await center.add(UNNotificationRequest(identifier: "achievement-\(a.id)", content: content, trigger: nil))
        }
    }

    /// With the app open the in-app banner already shows it, so the notification
    /// only goes to Notification Center rather than popping up a second banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.list])
    }
}

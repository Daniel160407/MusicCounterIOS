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
        case bestWeekendSeconds, dawnToDusk, hoursCovered, longestHabit, longestGap, daysSinceFirst
        case totalPlays, topTrackPlays, artistCount, trackCount, topArtistSeconds, serviceCount, favoriteCount
    }

    enum Unit { case time, days, count, flag }

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

        // Plays
        .init(id: "century", group: "Plays", symbol: "play.fill", title: "Century", text: "Play 100 tracks", metric: .totalPlays, goal: 100, unit: .count),
        .init(id: "thousand", group: "Plays", symbol: "play.square.stack.fill", title: "Thousand Plays", text: "Play 1,000 tracks", metric: .totalPlays, goal: 1000, unit: .count),
        .init(id: "jukebox", group: "Plays", symbol: "radio.fill", title: "Jukebox", text: "Play 5,000 tracks", metric: .totalPlays, goal: 5000, unit: .count),
        .init(id: "on-repeat", group: "Plays", symbol: "repeat", title: "On Repeat", text: "Play the same track 10 times", metric: .topTrackPlays, goal: 10, unit: .count),
        .init(id: "obsessed", group: "Plays", symbol: "repeat.1", title: "Obsessed", text: "Play the same track 50 times", metric: .topTrackPlays, goal: 50, unit: .count),
        .init(id: "broken-record", group: "Plays", symbol: "record.circle.fill", title: "Broken Record", text: "Play the same track 100 times", metric: .topTrackPlays, goal: 100, unit: .count),

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
        .init(id: "omnivore", group: "Variety", symbol: "globe", title: "Omnivore", text: "Listen on YouTube, YouTube Music, Spotify and iPhone", metric: .serviceCount, goal: 4, unit: .count),

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
        switch a.unit {
        case .flag: return ""
        case .time: return "\(formatDuration(value)) / \(formatDuration(a.goal))"
        case .days: return "\(Int(value)) / \(Int(a.goal)) days"
        case .count: return "\(Int(value).formatted()) / \(Int(a.goal).formatted())"
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
            .dawnToDusk: dawnToDusk,
            .hoursCovered: Double(hourTotals.filter { $0 >= activeDaySeconds }.count),
            .longestStreak: Double(activeRuns.longest),
            .longestHabit: Double(runs(habit).longest),
            .activeDays: Double(active.count),
            .longestGap: Double(activeRuns.longestGap),
            .daysSinceFirst: Double(daysSinceFirst),
            .totalPlays: Double(store.totalPlays),
            .topTrackPlays: Double(tracks.map(\.plays).max() ?? 0),
            .artistCount: Double(artists.count),
            .trackCount: Double(tracks.filter { $0.seconds >= 1 || $0.plays > 0 }.count),
            .topArtistSeconds: artists.first?.seconds ?? 0,
            .serviceCount: Double(store.services.filter { $0.source != Service.other && $0.seconds >= activeDaySeconds }.count),
            .favoriteCount: Double(store.stats.favorites.count),
        ]
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

    private var unlocked: [String: Date]
    private let store: Store
    private var cancellable: AnyCancellable?

    init(store: Store) {
        self.store = store
        let raw = UserDefaults.standard.dictionary(forKey: Self.unlockedKey) as? [String: Double] ?? [:]
        unlocked = raw.mapValues { Date(timeIntervalSince1970: $0) }
        unseen = Set(UserDefaults.standard.stringArray(forKey: Self.unseenKey) ?? [])
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
        statuses = Achievement.all.map { a in
            let value = metrics[a.metric] ?? 0
            if unlocked[a.id] == nil, value >= a.goal {
                unlocked[a.id] = Date()
                fresh.append(a)
            }
            return AchievementStatus(achievement: a, value: min(value, a.goal), unlockedAt: unlocked[a.id])
        }
        guard !fresh.isEmpty else { return [] }
        unseen.formUnion(fresh.map(\.id))
        save()
        if announce {
            // On screen the in-app banner shows it; otherwise the system notification is all you'd see.
            if UIApplication.shared.applicationState == .active { justUnlocked.append(contentsOf: fresh) }
            Task { await AchievementNotifier.shared.post(fresh) }
        }
        return fresh
    }

    func markSeen() {
        guard !unseen.isEmpty else { return }
        unseen = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(unlocked.mapValues { $0.timeIntervalSince1970 }, forKey: Self.unlockedKey)
        UserDefaults.standard.set(Array(unseen), forKey: Self.unseenKey)
    }
}

/// Posts a local notification for each badge earned.
final class AchievementNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AchievementNotifier()

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
            content.sound = .default
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

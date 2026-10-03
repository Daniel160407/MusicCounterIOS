import Foundation

@MainActor
final class Store: ObservableObject {
    static let maxHistory = 5000
    static let maxTracks = 1500
    static let maxFavorites = 300

    @Published private(set) var stats: Stats

    private let url: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("stats.json")

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Stats.self, from: data) {
            stats = decoded
        } else {
            stats = Stats()
        }
        pruneHistory()
    }

    func mutate(_ change: (inout Stats) -> Void) {
        change(&stats)
        save()
    }

    // MARK: - Recording

    private func credit(_ seconds: Double, at date: Date, in s: inout Stats) {
        let key = Self.dayFormatter.string(from: date)
        s.daily[key, default: 0] += seconds
        var hours = s.hourly[key] ?? Array(repeating: 0, count: 24)
        hours[Calendar.current.component(.hour, from: date)] += seconds
        s.hourly[key] = hours
    }

    func addTime(_ seconds: Double, to id: String, title: String, artist: String) {
        mutate { s in
            var t = s.tracks[id] ?? TrackStat(id: id, title: title, artist: artist)
            t.seconds += seconds
            t.lastPlayed = Date()
            s.tracks[id] = t
            credit(seconds, at: Date(), in: &s)
        }
    }

    /// `estimatedSeconds` is only passed for plays reconstructed from the library (not heard live).
    func addPlays(_ plays: Int, to id: String, title: String, artist: String, estimatedSeconds: Double = 0, on date: Date? = nil) {
        let when = date ?? Date()
        mutate { s in
            var t = s.tracks[id] ?? TrackStat(id: id, title: title, artist: artist)
            t.plays += plays
            t.seconds += estimatedSeconds
            t.lastPlayed = max(t.lastPlayed ?? .distantPast, when)
            s.tracks[id] = t
            if estimatedSeconds > 0 { credit(estimatedSeconds, at: when, in: &s) }

            s.history.append(HistoryEntry(trackID: id, title: title, artist: artist, at: when))
            s.history.sort { $0.at < $1.at }
            Self.trim(&s.history, retention: Self.currentRetention)
            Self.pruneTracks(&s)
        }
    }

    private static func pruneTracks(_ s: inout Stats) {
        guard s.tracks.count > maxTracks else { return }
        let removable = s.tracks.values
            .filter { s.favorites[$0.id] == nil }
            .sorted { $0.seconds < $1.seconds }
            .prefix(s.tracks.count - maxTracks)
        for t in removable { s.tracks[t.id] = nil }
    }

    // MARK: - History

    static var currentRetention: Retention {
        Retention(rawValue: UserDefaults.standard.string(forKey: Retention.storageKey) ?? "") ?? .forever
    }

    private static func trim(_ history: inout [HistoryEntry], retention: Retention) {
        if let interval = retention.interval {
            let cutoff = Date().addingTimeInterval(-interval)
            history.removeAll { $0.at < cutoff }
        }
        if history.count > maxHistory { history.removeFirst(history.count - maxHistory) }
    }

    /// Applies the current retention setting to stored history.
    func pruneHistory() {
        mutate { Self.trim(&$0.history, retention: Self.currentRetention) }
    }

    func clearHistory() {
        mutate { $0.history = [] }
    }

    // MARK: - Favorites

    func isFavorite(_ id: String) -> Bool { stats.favorites[id] != nil }

    func toggleFavorite(id: String, title: String, artist: String) {
        mutate { s in
            if s.favorites[id] != nil {
                s.favorites[id] = nil
            } else {
                s.favorites[id] = Favorite(id: id, title: title, artist: artist, addedAt: Date())
                if s.favorites.count > Self.maxFavorites,
                   let oldest = s.favorites.values.min(by: { $0.addedAt < $1.addedAt }) {
                    s.favorites[oldest.id] = nil
                }
            }
        }
    }

    /// Favorites, most played first; listening time breaks a tie, then the most recently starred.
    var favoriteTracks: [TrackStat] {
        stats.favorites.values
            .map { fav in
                stats.tracks[fav.id] ?? TrackStat(id: fav.id, title: fav.title, artist: fav.artist)
            }
            .sorted { a, b in
                if a.plays != b.plays { return a.plays > b.plays }
                if a.seconds != b.seconds { return a.seconds > b.seconds }
                return (stats.favorites[a.id]?.addedAt ?? .distantPast) > (stats.favorites[b.id]?.addedAt ?? .distantPast)
            }
    }

    // MARK: - Aggregates

    func reset() {
        mutate { s in
            s.tracks = [:]
            s.daily = [:]
            s.hourly = [:]
            s.history = []
            s.pendingLive = [:]
            // snapshot and favorites are kept, so old library plays aren't credited again
        }
    }

    var totalSeconds: Double { stats.tracks.values.reduce(0) { $0 + $1.seconds } }

    var totalPlays: Int { stats.tracks.values.reduce(0) { $0 + $1.plays } }

    var todaySeconds: Double { stats.daily[Self.dayFormatter.string(from: Date())] ?? 0 }

    /// Listening per artist, most listened first.
    var artists: [(name: String, seconds: Double, plays: Int)] {
        var map: [String: (Double, Int)] = [:]
        for t in stats.tracks.values {
            let cur = map[t.artist] ?? (0, 0)
            map[t.artist] = (cur.0 + t.seconds, cur.1 + t.plays)
        }
        return map.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.1 > $1.1 }
    }

    /// Listening per day for the last `n` days, oldest first, ending today.
    func lastDays(_ n: Int) -> [(date: Date, seconds: Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<n).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (d, stats.daily[Self.dayFormatter.string(from: d)] ?? 0)
        }
    }

    /// 24 hourly buckets (seconds) for the day `daysAgo` days back.
    func hours(daysAgo: Int) -> [Double] {
        guard let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) else {
            return Array(repeating: 0, count: 24)
        }
        return stats.hourly[Self.dayFormatter.string(from: d)] ?? Array(repeating: 0, count: 24)
    }

    /// Hours across all recorded days, for the "typical day" shape.
    var allTimeHours: [Double] {
        var total = Array(repeating: 0.0, count: 24)
        for h in stats.hourly.values { for i in 0..<24 { total[i] += h[i] } }
        return total
    }

    /// Consecutive days with listening, counting back from today (or yesterday if today is empty so far).
    var streak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if (stats.daily[Self.dayFormatter.string(from: day)] ?? 0) < 1,
           let y = cal.date(byAdding: .day, value: -1, to: day) { day = y }
        var count = 0
        while (stats.daily[Self.dayFormatter.string(from: day)] ?? 0) >= 1 {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stats) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

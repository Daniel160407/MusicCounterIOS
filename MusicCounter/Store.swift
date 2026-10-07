import Foundation

@MainActor
final class Store: ObservableObject {
    static let maxHistory = 5000
    static let maxTracks = 1500
    static let maxFavorites = 300

    @Published private(set) var stats: Stats

    /// Called after every change to `stats`, so sync can schedule an upload.
    var onChange: (() -> Void)?
    /// Called when a favorite is added (with it) or removed (with nil), keyed by `Store.sharedKey`.
    var onFavoriteChange: ((String, Favorite?) -> Void)?

    // Other devices' data (the browser extension, another phone), folded in for display only.
    private(set) var remoteTracks: [String: TrackStat] = [:]
    private(set) var remoteHistory: [HistoryEntry] = []
    /// Day -> service -> seconds.
    private var remoteDaily: [String: [String: Double]] = [:]
    /// Day -> 24 hours of service -> seconds.
    private var remoteHourly: [String: [[String: Double]]] = [:]
    private var remoteTotal: Double = 0
    private var remoteSources: [String: Double] = [:]

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
        // Entries recorded as "Unknown artist" before titles were parsed for one.
        for (id, t) in stats.tracks { stats.tracks[id]?.artist = ArtistName.resolve(t.artist, title: t.title) }
        for (id, f) in stats.favorites { stats.favorites[id]?.artist = ArtistName.resolve(f.artist, title: f.title) }
        for i in stats.history.indices {
            stats.history[i].artist = ArtistName.resolve(stats.history[i].artist, title: stats.history[i].title)
        }
        pruneHistory()
    }

    func mutate(_ change: (inout Stats) -> Void) {
        change(&stats)
        save()
        onChange?()
    }

    // MARK: - Other devices

    func setRemote(_ devices: [String: RemoteDevice]) {
        var tracks: [String: TrackStat] = [:]
        var daily: [String: [String: Double]] = [:]
        var hourly: [String: [[String: Double]]] = [:]
        var history: [HistoryEntry] = []
        var total = 0.0
        var sources: [String: Double] = [:]

        for device in devices.values {
            total += device.total
            // A phone's listening is all "ios"; a browser without the split can't be attributed.
            let split = device.sources.filter { $0.value > 0 }
            let fallback = device.platform == "ios" ? "ios" : Service.other
            sources.merge(split.isEmpty ? [fallback: device.total] : split, uniquingKeysWith: +)
            for (key, t) in device.tracks {
                var stat = tracks[key] ?? TrackStat(
                    id: key, title: t.title ?? "Unknown",
                    artist: ArtistName.resolve(t.artist, title: t.title),
                    source: t.source ?? device.platform)
                stat.seconds += t.seconds ?? 0
                stat.plays += t.plays ?? 0
                tracks[key] = stat
            }
            for (key, day) in device.days {
                daily[key, default: [:]].merge(day.services, uniquingKeysWith: +)
                var hours = hourly[key] ?? Array(repeating: [:], count: 24)
                for (hour, slice) in day.hours ?? [:] {
                    if let h = Int(hour), (0..<24).contains(h) { hours[h].merge(slice.services, uniquingKeysWith: +) }
                }
                hourly[key] = hours
            }
            for play in device.history {
                let source = play.source ?? device.platform
                history.append(HistoryEntry(
                    trackID: "\(source):\(play.id ?? play.title ?? "")",
                    title: play.title ?? "Unknown",
                    artist: ArtistName.resolve(play.artist, title: play.title),
                    at: Date(timeIntervalSince1970: play.at / 1000),
                    source: source, artwork: play.artwork))
            }
        }

        objectWillChange.send()
        remoteTracks = tracks
        remoteDaily = daily
        remoteHourly = hourly
        remoteHistory = history
        remoteTotal = total
        remoteSources = sources
    }

    /// Every track this phone and the other devices know about.
    var allTracks: [TrackStat] { Array(stats.tracks.values) + Array(remoteTracks.values) }

    /// `artist` plus any already-heard artist the title credits ("Irina Rimes x Delia - Petale").
    func creditedArtist(_ artist: String, title: String) -> String {
        ArtistName.withTitleArtists(artist, title: title, known: Set(allTracks.map(\.artist)))
    }

    /// Plays from every device, oldest first.
    var allHistory: [HistoryEntry] {
        remoteHistory.isEmpty ? stats.history : (stats.history + remoteHistory).sorted { $0.at < $1.at }
    }

    private func daySeconds(_ key: String) -> Double {
        dayServices(key).values.reduce(0, +)
    }

    /// A day's listening per service; this phone's own counts as "ios".
    private func dayServices(_ key: String) -> [String: Double] {
        var out = remoteDaily[key] ?? [:]
        if let local = stats.daily[key], local > 0 { out["ios", default: 0] += local }
        return out
    }

    private func dayHourServices(_ key: String) -> [[String: Double]] {
        var hours = remoteHourly[key] ?? Array(repeating: [:], count: 24)
        for (h, seconds) in (stats.hourly[key] ?? []).enumerated() where seconds > 0 && h < 24 {
            hours[h]["ios", default: 0] += seconds
        }
        return hours
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
            t.artist = artist
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
            t.artist = artist
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

    /// `source` is nil for a song in this phone's library, else the service of another device's track.
    func toggleFavorite(id: String, title: String, artist: String, source: String? = nil) {
        var changes: [(String, Favorite?)] = []
        mutate { s in
            if s.favorites[id] != nil {
                s.favorites[id] = nil
                changes.append((id, nil))
            } else {
                let fav = Favorite(id: id, title: title, artist: artist, addedAt: Date(), source: source)
                s.favorites[id] = fav
                changes.append((id, fav))
                if s.favorites.count > Self.maxFavorites,
                   let oldest = s.favorites.values.min(by: { $0.addedAt < $1.addedAt }) {
                    s.favorites[oldest.id] = nil
                    changes.append((oldest.id, nil))
                }
            }
        }
        for (id, fav) in changes { onFavoriteChange?(Self.sharedKey(id), fav) }
    }

    /// The key both apps use for a favorite: library songs get an "ios:" prefix, other
    /// devices' tracks already carry their service ("spotify:…").
    nonisolated static func sharedKey(_ id: String) -> String { id.contains(":") ? id : "ios:\(id)" }

    /// Replaces the favorites with the synced list (keyed by `sharedKey`).
    func replaceFavorites(_ shared: [String: Favorite]) {
        var next: [String: Favorite] = [:]
        for (key, fav) in shared {
            if key.hasPrefix("ios:") {
                let id = String(key.dropFirst(4))
                next[id] = Favorite(id: id, title: fav.title, artist: fav.artist, addedAt: fav.addedAt)
            } else {
                next[key] = Favorite(id: key, title: fav.title, artist: fav.artist, addedAt: fav.addedAt, source: fav.source)
            }
        }
        guard Set(next.keys) != Set(stats.favorites.keys) else { return }
        mutate { $0.favorites = next }
    }

    /// Favorites, most played first; listening time breaks a tie, then the most recently starred.
    var favoriteTracks: [TrackStat] {
        stats.favorites.values
            .map { fav in
                stats.tracks[fav.id] ?? remoteTracks[fav.id]
                    ?? TrackStat(id: fav.id, title: fav.title, artist: fav.artist, source: fav.source)
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

    /// This phone's listening only; what gets uploaded as the device total.
    var localSeconds: Double { stats.tracks.values.reduce(0) { $0 + $1.seconds } }

    var totalSeconds: Double { localSeconds + remoteTotal }

    var totalPlays: Int { allTracks.reduce(0) { $0 + $1.plays } }

    var todaySeconds: Double { daySeconds(Self.dayFormatter.string(from: Date())) }

    /// Listening per artist, most listened first.
    var artists: [(name: String, seconds: Double, plays: Int)] {
        var map: [String: (Double, Int)] = [:]
        for t in allTracks {
            let cur = map[t.artist] ?? (0, 0)
            map[t.artist] = (cur.0 + t.seconds, cur.1 + t.plays)
        }
        return map.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.1 > $1.1 }
    }

    /// Listening per day for the last `n` days, oldest first, ending today.
    /// `n` days ending `endingDaysAgo` days before today, oldest first.
    func lastDays(_ n: Int, endingDaysAgo: Int = 0) -> [DayListening] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<n).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -(offset + endingDaysAgo), to: today) else { return nil }
            return DayListening(date: d, services: dayServices(Self.dayFormatter.string(from: d)))
        }
    }

    /// 24 hourly buckets of service -> seconds for the day `daysAgo` days back.
    func hours(daysAgo: Int) -> [[String: Double]] {
        guard let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) else {
            return Array(repeating: [:], count: 24)
        }
        return dayHourServices(Self.dayFormatter.string(from: d))
    }

    /// Hours across all recorded days, for the "typical day" shape.
    var allTimeHours: [[String: Double]] {
        var total: [[String: Double]] = Array(repeating: [:], count: 24)
        for key in Set(stats.hourly.keys).union(remoteHourly.keys) {
            for (i, slice) in dayHourServices(key).enumerated() { total[i].merge(slice, uniquingKeysWith: +) }
        }
        return total
    }

    /// The earliest day with any listening recorded, on any device.
    var firstListeningDay: Date? {
        allDayTotals.filter { $0.value >= 1 }.keys.min().flatMap { Self.dayFormatter.date(from: $0) }
    }

    /// Seconds listened per day, every device, keyed "yyyy-MM-dd".
    var allDayTotals: [String: Double] {
        var out: [String: Double] = [:]
        for key in Set(stats.daily.keys).union(remoteDaily.keys) { out[key] = daySeconds(key) }
        return out
    }

    /// Each recorded day's 24 hours of service -> seconds, every device, keyed "yyyy-MM-dd".
    var allDayHourServices: [String: [[String: Double]]] {
        var out: [String: [[String: Double]]] = [:]
        for key in Set(stats.hourly.keys).union(remoteHourly.keys) { out[key] = dayHourServices(key) }
        return out
    }

    /// Whether listening from another device has been loaded.
    var hasRemote: Bool { remoteTotal > 0 || !remoteHistory.isEmpty }

    /// Each recorded day's 24 hourly totals, every device.
    var allDayHours: [[Double]] {
        Set(stats.hourly.keys).union(remoteHourly.keys).map { key in
            dayHourServices(key).map { $0.values.reduce(0, +) }
        }
    }

    /// All-time listening and plays per service, most listened first.
    var services: [ServiceTotal] {
        var seconds = remoteSources
        seconds["ios", default: 0] += localSeconds
        var plays: [String: Int] = [:]
        for t in allTracks { plays[t.source ?? "ios", default: 0] += t.plays }
        return Self.ranked(seconds, plays: plays)
    }

    /// Listening per service over the last `n` days (today included), most listened first.
    /// Time per service over the window, with plays counted from the history
    /// (which the retention setting may have trimmed for older windows).
    func services(lastDays n: Int, endingDaysAgo: Int = 0) -> [ServiceTotal] {
        let days = lastDays(n, endingDaysAgo: endingDaysAgo)
        var seconds: [String: Double] = [:]
        for day in days { seconds.merge(day.services, uniquingKeysWith: +) }
        var plays: [String: Int] = [:]
        if let from = days.first?.date, let last = days.last?.date,
           let until = Calendar.current.date(byAdding: .day, value: 1, to: last) {
            for entry in allHistory where entry.at >= from && entry.at < until {
                plays[entry.source ?? "ios", default: 0] += 1
            }
        }
        return Self.ranked(seconds, plays: plays)
    }

    private static func ranked(_ seconds: [String: Double], plays: [String: Int]) -> [ServiceTotal] {
        seconds.filter { $0.value >= 1 }
            .map { ServiceTotal(source: $0.key, seconds: $0.value, plays: plays[$0.key] ?? 0) }
            .sorted { $0.seconds > $1.seconds }
    }

    /// Consecutive days with listening, counting back from today (or yesterday if today is empty so far).
    var streak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if daySeconds(Self.dayFormatter.string(from: day)) < 1,
           let y = cal.date(byAdding: .day, value: -1, to: day) { day = y }
        var count = 0
        while daySeconds(Self.dayFormatter.string(from: day)) >= 1 {
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

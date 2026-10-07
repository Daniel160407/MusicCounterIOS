import Foundation

struct TrackStat: Codable, Identifiable {
    var id: String            // MPMediaEntityPersistentID as string; "source:id" for another device's track
    var title: String
    var artist: String
    var seconds: Double = 0   // time listened
    var plays: Int = 0
    var lastPlayed: Date?
    /// nil for songs in this phone's library; "youtube", "ytmusic", "spotify" for ones synced from the browser.
    var source: String?
}

/// One day's listening, split by service.
struct DayListening {
    var date: Date
    var services: [String: Double]
    var seconds: Double { services.values.reduce(0, +) }
}

struct ServiceTotal: Identifiable {
    var source: String
    var seconds: Double
    var plays: Int
    var id: String { source }
}

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    var trackID: String
    var title: String
    var artist: String
    var at: Date
    var source: String?
    var artwork: String?
}

struct Favorite: Codable {
    var id: String
    var title: String
    var artist: String
    var addedAt: Date
    var source: String?
}

enum Retention: String, CaseIterable, Identifiable {
    case week, twoWeeks, month, forever
    var id: String { rawValue }
    static let storageKey = "historyRetention"

    /// The value the browser extension uses for the same setting.
    var shared: String { self == .twoWeeks ? "2weeks" : rawValue }

    init?(shared: String) {
        self.init(rawValue: shared == "2weeks" ? "twoWeeks" : shared)
    }

    var label: String {
        switch self {
        case .week: return "1 week"
        case .twoWeeks: return "2 weeks"
        case .month: return "1 month"
        case .forever: return "Forever"
        }
    }

    /// Seconds to keep, or nil to keep everything (still capped by `Store.maxHistory`).
    var interval: TimeInterval? {
        switch self {
        case .week: return 7 * 86_400
        case .twoWeeks: return 14 * 86_400
        case .month: return 30 * 86_400
        case .forever: return nil
        }
    }
}

struct Stats: Codable {
    var tracks: [String: TrackStat] = [:]
    /// Library playCount seen at the last reconcile, used to detect plays that happened while the app was closed.
    var snapshot: [String: Int] = [:]
    /// Plays already credited live, so reconcile doesn't count them twice.
    var pendingLive: [String: Int] = [:]
    /// "yyyy-MM-dd" -> seconds listened.
    var daily: [String: Double] = [:]
    /// "yyyy-MM-dd" -> 24 buckets of seconds listened.
    var hourly: [String: [Double]] = [:]
    /// One entry per counted play, oldest first.
    var history: [HistoryEntry] = []
    var favorites: [String: Favorite] = [:]
    var baselined = false

    init() {}

    // Older saved files lack the newer keys, so every field falls back to its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try c.decodeIfPresent([String: TrackStat].self, forKey: .tracks) ?? [:]
        snapshot = try c.decodeIfPresent([String: Int].self, forKey: .snapshot) ?? [:]
        pendingLive = try c.decodeIfPresent([String: Int].self, forKey: .pendingLive) ?? [:]
        daily = try c.decodeIfPresent([String: Double].self, forKey: .daily) ?? [:]
        hourly = try c.decodeIfPresent([String: [Double]].self, forKey: .hourly) ?? [:]
        history = try c.decodeIfPresent([HistoryEntry].self, forKey: .history) ?? []
        favorites = try c.decodeIfPresent([String: Favorite].self, forKey: .favorites) ?? [:]
        baselined = try c.decodeIfPresent(Bool.self, forKey: .baselined) ?? false
    }
}

enum ArtistName {
    static let unknown = "Unknown artist"

    /// The tagged artist, or — when it's missing or "Unknown" — the part before
    /// " - " in a title like "Miyagi - Karabli".
    static func resolve(_ artist: String?, title: String?) -> String {
        let tagged = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !isUnknown(tagged) { return tagged }
        return fromTitle(title) ?? unknown
    }

    static func isUnknown(_ artist: String) -> Bool {
        let a = artist.lowercased()
        return a.isEmpty || a == "unknown artist" || a == "<unknown>" || a == "unknown"
    }

    /// Collaborations are often credited in the title rather than the artist tag —
    /// "Irina Rimes x Delia - Petale" tagged "Irina Rimes". Any `known` artist who
    /// appears in the title's credit part (the side of " - " that names the artist,
    /// or after "feat." / "ft." / "(with") is attached: "Irina Rimes, Delia", the
    /// shape Spotify uses. Longer names win, so "Delia Matache" isn't also "Delia".
    /// Mirrors `withTitleArtists` in the extension's background.js.
    static func withTitleArtists(_ artist: String, title: String, known: some Sequence<String>) -> String {
        let credited = isUnknown(artist) ? [] : artist.components(separatedBy: ", ")
        var regions: [String] = []
        if let dash = title.range(of: #"\s[-–—]\s"#, options: .regularExpression), dash.lowerBound > title.startIndex {
            // Usually "Artists - Song", but "Song - Artists" exists too: take the side
            // that names the artist we already have.
            let head = String(title[..<dash.lowerBound])
            let tail = String(title[dash.upperBound...])
            let namesArtist = { (side: String) in credited.contains { matches($0, in: side) } }
            regions.append(!namesArtist(head) && namesArtist(tail) ? tail : head)
        }
        for m in featureRegex.matches(in: title, range: NSRange(title.startIndex..., in: title)) {
            if let r = Range(m.range(at: 1), in: title) { regions.append(String(title[r])) }
        }
        if regions.isEmpty { return artist }

        var names = Set<String>()
        for key in known {
            names.insert(key.trimmingCharacters(in: .whitespaces))
            for part in key.components(separatedBy: ", ") { names.insert(part.trimmingCharacters(in: .whitespaces)) }
        }

        // Blank out the artists already credited so their names, or pieces of them,
        // can't match again; then each found name, longest first.
        var credits = regions.joined(separator: " | ") as NSString
        func blank(_ name: String) -> Int? {
            let re = matcher(name)
            let first = re.rangeOfFirstMatch(in: credits as String, range: NSRange(location: 0, length: credits.length))
            guard first.location != NSNotFound else { return nil }
            for m in re.matches(in: credits as String, range: NSRange(location: 0, length: credits.length)) {
                credits = credits.replacingCharacters(in: m.range, with: String(repeating: " ", count: m.range.length)) as NSString
            }
            return first.location
        }
        for name in credited { _ = blank(name) }

        var found: [(name: String, at: Int)] = []
        let candidates = names
            .filter { $0.count >= 2 && !isUnknown($0) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
        for name in candidates where !credited.contains(where: { matches(name, in: $0) }) {
            if let at = blank(name) { found.append((name, at)) }
        }
        if found.isEmpty { return artist }
        return (credited + found.sorted { $0.at < $1.at }.map(\.name)).joined(separator: ", ")
    }

    private static let featureRegex = try! NSRegularExpression(
        pattern: #"(?:\bfeat\.?|\bft\.?|\bfeaturing|[(\[]\s*with)\s+([^)\]]+)"#, options: .caseInsensitive)

    private static func matcher(_ name: String) -> NSRegularExpression {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])"# + escaped + #"(?![\p{L}\p{N}])"#, options: .caseInsensitive)
    }

    private static func matches(_ name: String, in text: String) -> Bool {
        matcher(name).firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func fromTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        for sep in [" - ", " – ", " — "] {
            if let r = title.range(of: sep) {
                let name = title[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { return name }
            }
        }
        return nil
    }
}

import Foundation

struct TrackStat: Codable, Identifiable {
    var id: String            // MPMediaEntityPersistentID as string
    var title: String
    var artist: String
    var seconds: Double = 0   // time listened
    var plays: Int = 0
    var lastPlayed: Date?
}

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    var trackID: String
    var title: String
    var artist: String
    var at: Date
}

struct Favorite: Codable {
    var id: String
    var title: String
    var artist: String
    var addedAt: Date
}

enum Retention: String, CaseIterable, Identifiable {
    case week, twoWeeks, month, forever
    var id: String { rawValue }
    static let storageKey = "historyRetention"

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

import Foundation
import SwiftUI

/// The JSON both apps store in Firestore parts (see sync.js in the browser extension).
/// Every field is optional so a part written by a newer or older version still decodes.
enum Shared {
    struct Track: Codable {
        var id: String?
        var title: String?
        var artist: String?
        var source: String?
        var seconds: Double?
        var plays: Int?
    }

    struct Artist: Codable {
        var seconds: Double?
        var source: String?
    }

    /// Seconds per service alongside the total, on a day and on each of its hours.
    struct Hour: Codable {
        var total: Double?
        var youtube: Double?
        var ytmusic: Double?
        var spotify: Double?
        var ios: Double?

        var services: [String: Double] {
            Service.split(total: total, ["youtube": youtube, "ytmusic": ytmusic, "spotify": spotify, "ios": ios])
        }
    }

    struct Day: Codable {
        var total: Double?
        var youtube: Double?
        var ytmusic: Double?
        var spotify: Double?
        var ios: Double?
        var hours: [String: Hour]?

        var services: [String: Double] {
            Service.split(total: total, ["youtube": youtube, "ytmusic": ytmusic, "spotify": spotify, "ios": ios])
        }
    }

    struct DayOut: Encodable {
        var total: Double
        var ios: Double
        var hours: [String: [String: Double]]
    }

    struct Play: Codable {
        var id: String?
        var title: String?
        var artist: String?
        var source: String?
        var artwork: String?
        /// Milliseconds since 1970.
        var at: Double
    }
}

/// Another device's synced data, as last fetched.
struct RemoteDevice {
    var name: String
    var platform: String
    var total: Double
    /// All-time seconds per service, from the device document.
    var sources: [String: Double] = [:]
    var tracks: [String: Shared.Track] = [:]
    var days: [String: Shared.Day] = [:]
    var history: [Shared.Play] = []
}

/// Splits this phone's stats into the named parts uploaded under devices/{id}/parts.
enum SyncParts {
    /// Firestore caps a string field just under 1 MiB; leave room for the envelope.
    static let maxPartBytes = 900_000

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        // Stable output, so an unchanged part hashes the same and isn't uploaded again.
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static func round(_ x: Double) -> Double { (x * 10).rounded() / 10 }

    private static func json<T: Encodable>(_ value: T) -> String {
        (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    static func build(_ s: Stats) -> [String: String] {
        var parts: [String: String] = [:]

        var tracks: [String: Shared.Track] = [:]
        var artistSeconds: [String: Double] = [:]
        for t in s.tracks.values {
            tracks[Store.sharedKey(t.id)] = Shared.Track(
                id: t.id, title: t.title, artist: t.artist, source: "ios",
                seconds: round(t.seconds), plays: t.plays)
            artistSeconds[t.artist, default: 0] += t.seconds
        }
        parts["tracks"] = json(tracks)
        parts["artists"] = json(artistSeconds.mapValues { Shared.Artist(seconds: round($0), source: "ios") })

        var years: [String: [String: Shared.DayOut]] = [:]
        for (day, total) in s.daily {
            var hours: [String: [String: Double]] = [:]
            for (hour, seconds) in (s.hourly[day] ?? []).enumerated() where seconds > 0 {
                hours[String(hour)] = ["total": round(seconds), "ios": round(seconds)]
            }
            years[String(day.prefix(4)), default: [:]][day] = Shared.DayOut(total: round(total), ios: round(total), hours: hours)
        }
        for (year, days) in years { parts["days-\(year)"] = json(days) }

        // One part per month, split further only if a month is unusually heavy.
        let months = Dictionary(grouping: s.history) { monthFormatter.string(from: $0.at) }
        for (month, entries) in months {
            var chunk: [Shared.Play] = []
            var bytes = 2
            var index = 1
            for e in entries.sorted(by: { $0.at < $1.at }) {
                let play = Shared.Play(
                    id: e.trackID, title: e.title, artist: e.artist, source: "ios", artwork: "",
                    at: (e.at.timeIntervalSince1970 * 1000).rounded())
                let size = e.title.utf8.count + e.artist.utf8.count + e.trackID.utf8.count + 90
                if !chunk.isEmpty && bytes + size > maxPartBytes {
                    parts["history-\(month)-\(index)"] = json(chunk)
                    index += 1
                    chunk = []
                    bytes = 2
                }
                chunk.append(play)
                bytes += size
            }
            parts["history-\(month)-\(index)"] = json(chunk)
        }
        return parts
    }

    /// FNV-1a; only ever compared with hashes this phone wrote itself.
    static func hash(_ text: String) -> String {
        var h: UInt32 = 0x811c9dc5
        for byte in text.utf8 {
            h ^= UInt32(byte)
            h = h &* 0x01000193
        }
        return "\(String(h, radix: 36))-\(text.utf8.count)"
    }
}

/// The services listening is split by, in the extension's order and colours.
enum Service {
    static let all = ["ytmusic", "youtube", "spotify", "ios"]
    /// Listening recorded before the per-service split existed.
    static let other = "other"

    static func color(_ source: String) -> Color {
        switch source {
        case "youtube": return Color(red: 1.0, green: 0.31, blue: 0.27)
        case "ytmusic": return Color(red: 1.0, green: 0.54, blue: 0.24)
        case "spotify": return Color(red: 0.12, green: 0.84, blue: 0.38)
        case "ios": return Color(red: 0.29, green: 0.66, blue: 1.0)
        default: return Color.gray
        }
    }

    static func label(_ source: String) -> String {
        source == other ? "Other" : WebLink.label(source)
    }

    /// Entries in chart order, "other" and unknown services last.
    static func ordered(_ services: [String: Double]) -> [(key: String, value: Double)] {
        services.filter { $0.value > 0 }.sorted { (all.firstIndex(of: $0.key) ?? 99, $0.key) < (all.firstIndex(of: $1.key) ?? 99, $1.key) }
    }

    /// The non-zero services, with any of the total they don't account for as "other".
    static func split(total: Double?, _ parts: [String: Double?]) -> [String: Double] {
        var out = parts.compactMapValues { $0 }.filter { $0.value > 0 }
        let rest = (total ?? 0) - out.values.reduce(0, +)
        if rest >= 1 { out[other] = rest }
        return out
    }
}

/// Where another device's track lives on the web, mirroring the extension's links.
enum WebLink {
    static func label(_ source: String) -> String {
        switch source {
        case "youtube": return "YouTube"
        case "ytmusic": return "YouTube Music"
        case "spotify": return "Spotify"
        case "ios": return "iPhone"
        default: return source
        }
    }

    /// The id after the "source:" prefix of a shared key.
    static func rawID(_ key: String) -> String {
        guard let colon = key.firstIndex(of: ":") else { return key }
        return String(key[key.index(after: colon)...])
    }

    private static let queryAllowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    private static func isYouTubeID(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    }

    static func track(source: String, key: String, title: String, artist: String) -> URL? {
        let id = rawID(key)
        let query = [artist, title].filter { !$0.isEmpty }.joined(separator: " ")
            .addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? ""
        switch source {
        case "spotify":
            let isTrack = id.range(of: "^[A-Za-z0-9]{22}$", options: .regularExpression) != nil
            return URL(string: isTrack ? "https://open.spotify.com/track/\(id)" : "https://open.spotify.com/search/\(query)")
        case "ytmusic":
            // Searches go to YouTube, never YouTube Music, as in the extension.
            return URL(string: isYouTubeID(id) ? "https://music.youtube.com/watch?v=\(id)" : "https://www.youtube.com/results?search_query=\(query)")
        case "youtube":
            return URL(string: isYouTubeID(id) ? "https://www.youtube.com/watch?v=\(id)" : "https://www.youtube.com/results?search_query=\(query)")
        default:
            // Another phone's library song: the nearest place to play it.
            return URL(string: "https://www.youtube.com/results?search_query=\(query)")
        }
    }

    static func thumbnail(source: String, key: String, artwork: String? = nil) -> URL? {
        let id = rawID(key)
        if (source == "youtube" || source == "ytmusic") && isYouTubeID(id) {
            return URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
        }
        if let artwork, !artwork.isEmpty { return URL(string: artwork) }
        return nil
    }
}

/// A song loaded in a browser running the extension, read from `users/{uid}/live/{deviceID}`
/// (written by the extension's live.js). Its buttons go back through
/// `users/{uid}/commands/{deviceID}` as `command: { id, action, at }` (plus `value`, 0–2,
/// for action `volume`).
struct RemoteTrack: Equatable {
    /// A playing track is rewritten every minute; one this quiet means the browser went away.
    static let playingTimeout: TimeInterval = 3 * 60
    /// The extension stops offering a track paused this long, so it's hidden here too.
    static let pausedTimeout: TimeInterval = 30 * 60

    let deviceID: String
    let deviceName: String
    let source: String
    let id: String
    let title: String
    let artist: String
    let artwork: String
    var paused: Bool
    /// The browser player's volume, 0–`maxVolume`; nil when the page can't tell.
    var volume: Double?
    /// 2 where the extension can boost the page past 100% (YouTube, YouTube Music), else 1.
    let maxVolume: Double
    /// The playlist this song is part of, while the browser is playing one.
    let playlist: PlaylistProgress?
    let updatedAt: Date

    init?(deviceID: String, data: [String: Any]) {
        guard let track = data["track"] as? [String: Any], let source = track["source"] as? String else { return nil }
        func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
        func date(_ value: Any?) -> Date { Date(timeIntervalSince1970: (number(value) ?? 0) / 1000) }
        self.deviceID = deviceID
        deviceName = data["name"] as? String ?? "Browser"
        self.source = source
        id = track["id"] as? String ?? ""
        title = track["title"] as? String ?? ""
        artist = track["artist"] as? String ?? ""
        artwork = track["artwork"] as? String ?? ""
        paused = track["paused"] as? Bool ?? false
        let maxVolume = min(max(number(track["maxVolume"]) ?? 1, 1), 2)
        self.maxVolume = maxVolume
        volume = number(track["volume"]).map { min(max($0, 0), maxVolume) }
        playlist = (track["playlist"] as? [String: Any]).flatMap(PlaylistProgress.init)
        updatedAt = date(data["updatedAt"])
    }

    func isFresh(now: Date) -> Bool {
        now.timeIntervalSince(updatedAt) < (paused ? Self.pausedTimeout : Self.playingTimeout)
    }

    /// The key the extension files this track's stats and favorite under.
    var key: String { "\(source):\(id.isEmpty ? title : id)" }

    var thumbnail: URL? { WebLink.thumbnail(source: source, key: key, artwork: artwork) }
}

/// How far a browser is through a playlist: `index` is 0-based.
struct PlaylistProgress: Equatable {
    let id: String
    let name: String
    let index: Int
    let count: Int

    init?(_ data: [String: Any]) {
        guard let id = data["id"] as? String else { return nil }
        self.id = id
        name = data["name"] as? String ?? ""
        index = (data["index"] as? NSNumber)?.intValue ?? 0
        count = (data["count"] as? NSNumber)?.intValue ?? 0
    }

    var label: String { "\(name) · \(min(index + 1, count)) of \(count)" }
}

/// A playlist mixing YouTube, YouTube Music and Spotify songs, shared with the extension
/// through `users/{uid}/playlists/{id}` (see playlists.js). Only a browser can play one:
/// it opens each song in its service's tab and starts the next when it finishes.
struct WebPlaylist: Identifiable, Equatable {
    static let maxPlaylists = 100
    static let maxTracks = 500
    static let maxName = 80

    let id: String
    var name: String
    var tracks: [PlaylistTrack]
    var createdAt: Double
    var updatedAt: Double

    init(id: String = UUID().uuidString.lowercased(), name: String, tracks: [PlaylistTrack] = []) {
        let now = (Date().timeIntervalSince1970 * 1000).rounded()
        self.id = id
        self.name = Self.clean(name)
        self.tracks = tracks
        createdAt = now
        updatedAt = now
    }

    init?(data: [String: Any]) {
        guard let id = data["id"] as? String, !id.isEmpty else { return nil }
        self.id = id
        name = Self.clean(data["name"] as? String ?? "")
        tracks = (data["tracks"] as? [[String: Any]] ?? []).map(PlaylistTrack.init(data:))
        createdAt = (data["createdAt"] as? NSNumber)?.doubleValue ?? 0
        updatedAt = (data["updatedAt"] as? NSNumber)?.doubleValue ?? 0
    }

    /// Every field, as the extension writes them.
    var data: [String: Any] {
        ["id": id, "name": name, "tracks": tracks.map(\.data), "createdAt": createdAt, "updatedAt": updatedAt]
    }

    static func clean(_ name: String) -> String {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxName))
        return trimmed.isEmpty ? "Untitled playlist" : trimmed
    }

    func contains(_ track: PlaylistTrack) -> Bool { tracks.contains { $0.key == track.key } }

    /// The services in it, in chart order.
    var services: [String] { Service.all.filter { s in tracks.contains { $0.source == s } } }
}

struct PlaylistTrack: Equatable {
    static let sources = ["youtube", "ytmusic", "spotify", "ios"]

    let source: String
    /// The service's own id: a video id, a Spotify track id, or a library song's persistent ID.
    let id: String
    let title: String
    let artist: String

    init(source: String?, id: String, title: String, artist: String) {
        let source = source ?? "ios"
        self.source = Self.sources.contains(source) ? source : "youtube"
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// From a stats track: another device's carries a "source:id" key, a library song its persistent ID.
    init(source: String?, key: String, title: String, artist: String) {
        self.init(source: source, id: source == nil ? key : WebLink.rawID(key), title: title, artist: artist)
    }

    init(data: [String: Any]) {
        self.init(source: data["source"] as? String, id: data["id"] as? String ?? "",
                  title: data["title"] as? String ?? "", artist: data["artist"] as? String ?? "")
    }

    var data: [String: Any] { ["source": source, "id": id, "title": title, "artist": artist] }

    /// The key the stats file this song under, so a song is only added to a playlist once.
    var key: String { "\(source):\(id.isEmpty ? title : id)" }

    var thumbnail: URL? { WebLink.thumbnail(source: source, key: key) }
}

/// A pasted YouTube, YouTube Music or Spotify song link, read the way the extension's
/// playlists.js reads it, and its title fetched from the site's public oEmbed endpoint.
enum SongLink {
    static func parse(_ text: String) -> (source: String, id: String)? {
        guard let url = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              var host = url.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let isYouTube = { (id: String) in id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil }
        switch host {
        case "youtu.be":
            let id = url.path.split(separator: "/").first.map(String.init) ?? ""
            return isYouTube(id) ? ("youtube", id) : nil
        case "youtube.com", "m.youtube.com", "music.youtube.com":
            let parts = url.path.split(separator: "/").map(String.init)
            let id = parts.first == "shorts" && parts.count > 1
                ? parts[1]
                : url.queryItems?.first { $0.name == "v" }?.value ?? ""
            return isYouTube(id) ? (host == "music.youtube.com" ? "ytmusic" : "youtube", id) : nil
        case "open.spotify.com":
            // Localised links carry a prefix: /intl-de/track/{id}.
            let parts = url.path.split(separator: "/").map(String.init)
            guard let at = parts.firstIndex(of: "track"), at + 1 < parts.count else { return nil }
            let id = parts[at + 1]
            return id.range(of: "^[A-Za-z0-9]{22}$", options: .regularExpression) != nil ? ("spotify", id) : nil
        default:
            return nil
        }
    }

    /// The song, titled when the site answers; offline it keeps its id as the title.
    static func resolve(_ text: String) async -> PlaylistTrack? {
        guard let link = parse(text) else { return nil }
        let page = link.source == "spotify"
            ? "https://open.spotify.com/track/\(link.id)"
            : "https://www.youtube.com/watch?v=\(link.id)"
        var endpoint = URLComponents(string: link.source == "spotify"
            ? "https://open.spotify.com/oembed" : "https://www.youtube.com/oembed")!
        endpoint.queryItems = [URLQueryItem(name: "url", value: page), URLQueryItem(name: "format", value: "json")]
        var title = link.id
        var artist = ""
        if let url = endpoint.url,
           let (data, response) = try? await URLSession.shared.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let t = json["title"] as? String, !t.isEmpty { title = t }
            // Spotify's answer names the track only; YouTube's names the channel.
            if link.source != "spotify", let author = json["author_name"] as? String {
                artist = author.hasSuffix(" - Topic") ? String(author.dropLast(8)) : author
            }
        }
        return PlaylistTrack(source: link.source, id: link.id, title: title, artist: artist)
    }
}

/// A browser signed in to the same account, which can be asked to play a song.
struct Browser: Identifiable, Equatable {
    let id: String
    let name: String
    let lastSeen: Date
}

/// A song to open in the browser, as live.js's `open` command takes it. The extension
/// builds the link the same way its popup does: the track itself when the id is a usable
/// one, else a search (a YouTube search for a song from an iPhone library).
struct BrowserSong {
    let source: String
    let trackID: String
    let title: String
    let artist: String

    init(source: String?, key: String, title: String, artist: String) {
        self.source = source ?? "ios"
        // A library song's persistent ID means nothing to a web page.
        trackID = source == nil ? "" : WebLink.rawID(key)
        self.title = title
        self.artist = artist
    }
}

/// The browser player's buttons the phone can press; raw values match live.js.
enum BrowserAction: String {
    case previous = "prev"
    case playPause
    case next
}

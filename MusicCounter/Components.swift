import SwiftUI
import Charts
import MediaPlayer

enum Theme {
    static let gradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.30, blue: 0.45), Color(red: 1.0, green: 0.60, blue: 0.25)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let accent = Color(red: 1.0, green: 0.38, blue: 0.40)
}

func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds)
    let h = s / 3600, m = (s % 3600) / 60
    if h > 0 { return m == 0 ? "\(h)h" : "\(h)h \(m)m" }
    if m > 0 { return "\(m)m" }
    return "\(s)s"
}

/// The app logo alone in the middle of the screen, like YouTube's launch, while the other devices' stats
/// are first fetched from Firestore. Matches the launch screen, so the app opens straight into it.
struct SyncSplash: View {
    @EnvironmentObject var sync: Sync
    /// Never holds the app back for long, e.g. when offline.
    @State private var timedOut = false

    var body: some View {
        ZStack {
            if sync.isLoading && !timedOut {
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .overlay(Image("AppLogo"))
                    .transition(.opacity)
                    .task {
                        guard (try? await Task.sleep(nanoseconds: 10_000_000_000)) != nil else { return }
                        timedOut = true
                    }
            }
        }
        .animation(.easeOut(duration: 0.3), value: sync.isLoading && !timedOut)
        .onChange(of: sync.isLoading) { loading in
            // A later sign-in gets the full wait again.
            if loading { timedOut = false }
        }
    }
}

struct Card<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title).font(.headline)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    /// Colours chart series by service, naming only the services present.
    func serviceColors(_ sources: [String]) -> some View {
        let present = Service.all.filter(sources.contains) + Set(sources).subtracting(Service.all).sorted()
        return chartForegroundStyleScale(domain: present.map(Service.label), range: present.map(Service.color))
            .chartLegend(present.count > 1 ? .visible : .hidden)
    }
}

/// Listening split by service, as in the extension's "By service" list.
/// Bars and columns grow in when they appear and whenever `key` (the range,
/// period or day on show) changes — not when the numbers merely tick up.
private struct GrowIn<Key: Equatable>: ViewModifier {
    @Binding var grown: Bool
    let key: Key
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onAppear(perform: replay)
            .onChange(of: key) { _ in replay() }
    }

    private func replay() {
        guard !reduceMotion else { grown = true; return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { grown = false }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { grown = true }
        }
    }
}

extension View {
    func growIn<Key: Equatable>(_ grown: Binding<Bool>, key: Key) -> some View {
        modifier(GrowIn(grown: grown, key: key))
    }
}

struct ServiceBreakdown: View {
    let services: [ServiceTotal]
    /// What the breakdown covers (a period, "today"…); the bars grow in again when it changes.
    var key: String = ""
    @State private var grown = false

    var body: some View {
        let total = services.reduce(0) { $0 + $1.seconds }
        let max = services.first?.seconds ?? 1
        Group {
        if services.isEmpty {
            Text("Nothing recorded yet.").font(.subheadline).foregroundStyle(.secondary)
        }
        ForEach(services) { s in
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Service.label(s.source)).font(.subheadline.weight(.semibold))
                    Text("\(Int((s.seconds / Swift.max(total, 1) * 100).rounded()))%")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if s.plays > 0 {
                        Text("\(s.plays) \(s.plays == 1 ? "play" : "plays")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(formatDuration(s.seconds)).font(.subheadline.weight(.medium)).monospacedDigit()
                }
                GeometryReader { geo in
                    Capsule().fill(Service.color(s.source))
                        .frame(width: grown ? geo.size.width * CGFloat(max > 0 ? s.seconds / max : 0) : 0)
                }
                .frame(height: 4)
            }
        }
        }
        .growIn($grown, key: key)
    }
}

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 14
    /// Splits the filled arc into coloured parts by share; the theme gradient when empty.
    var segments: [(color: Color, share: Double)] = []

    var body: some View {
        let fill = min(max(progress, 0.001), 1)
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            if segments.isEmpty {
                arc(to: fill).stroke(Theme.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .animation(.easeOut(duration: 0.8), value: fill)
            } else {
                // Each part is drawn from the start of the ring to its own end, last part first, so the
                // earlier parts sit on top and their rounded ends overlap the next colour.
                let total = segments.reduce(0) { $0 + $1.share }
                let ends = segments.indices.map { i in
                    segments[...i].reduce(0) { $0 + $1.share } / max(total, .ulpOfOne) * fill
                }
                ForEach(segments.indices.reversed(), id: \.self) { i in
                    arc(to: ends[i]).stroke(segments[i].color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .animation(.easeOut(duration: 0.8), value: ends[i])
                }
            }
        }
    }

    private func arc(to end: Double) -> some Shape {
        Circle().trim(from: 0, to: end).rotation(.degrees(-90))
    }
}

struct EqualizerView: View {
    var active: Bool
    @State private var animate = false
    private let speeds: [Double] = [0.45, 0.6, 0.38, 0.52]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(Theme.gradient)
                    .frame(width: 4, height: active && animate ? 22 : 6)
                    .animation(
                        active
                            ? .easeInOut(duration: speeds[i]).repeatForever(autoreverses: true).delay(Double(i) * 0.08)
                            : .default,
                        value: animate)
            }
        }
        .frame(height: 22, alignment: .bottom)
        .onAppear { animate = true }
    }
}

/// Artwork looked up from the media library by persistent ID, cached in memory.
struct ArtworkView: View {
    let id: String
    var size: CGFloat = 48
    /// Cover for another device's track, which the media library doesn't have.
    var remoteURL: URL? = nil
    @State private var image: UIImage?

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let remoteURL {
                AsyncImage(url: remoteURL) { $0.resizable().scaledToFill() } placeholder: { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .task(id: id) { load() }
    }

    private var placeholder: some View {
        ZStack {
            Theme.gradient.opacity(0.25)
            Image(systemName: "music.note").foregroundStyle(Theme.accent)
        }
    }

    private func load() {
        let key = id as NSString
        if let cached = Self.cache.object(forKey: key) { image = cached; return }
        guard MPMediaLibrary.authorizationStatus() == .authorized, let pid = UInt64(id) else { return }
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: pid), forProperty: MPMediaItemPropertyPersistentID))
        if let art = query.items?.first?.artwork?.image(at: CGSize(width: size * 3, height: size * 3)) {
            Self.cache.setObject(art, forKey: key)
            image = art
        }
    }
}

/// Context-menu items that send a song to each signed-in browser to play there.
/// Shows nothing when signed out or no browser has synced recently.
struct PlayOnBrowserItems: View {
    @EnvironmentObject var sync: Sync
    let song: BrowserSong

    var body: some View {
        ForEach(sync.browsers) { browser in
            Button {
                haptic()
                sync.play(song, on: browser)
            } label: {
                Label("Play on \(browser.name)", systemImage: "desktopcomputer")
            }
        }
    }
}

struct StarButton: View {
    @EnvironmentObject var store: Store
    let id: String
    let title: String
    let artist: String
    var source: String? = nil

    var body: some View {
        let on = store.isFavorite(id)
        Button {
            store.toggleFavorite(id: id, title: title, artist: artist, source: source)
        } label: {
            Image(systemName: on ? "star.fill" : "star")
                .foregroundStyle(on ? Color.yellow : Color.secondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Remove from favorites" : "Add to favorites")
    }
}

/// A ranked song row: tap the row to play it, tap the star to favorite it.
/// Another device's track opens on the service it was played on instead.
struct TrackRow: View {
    @EnvironmentObject var tracker: Tracker
    @Environment(\.openURL) private var openURL
    let track: TrackStat
    var rank: Int?
    /// 0...1 length of the little bar under the title; nil hides it.
    var ratio: Double?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                if let rank {
                    Text("\(rank)")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                        .frame(width: 22)
                }
                ArtworkView(id: track.id, size: 46,
                            remoteURL: track.source.flatMap { WebLink.thumbnail(source: $0, key: track.id) })
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(track.source.map { "\(track.artist) · \(WebLink.label($0))" } ?? track.artist)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let ratio {
                        GeometryReader { geo in
                            Capsule().fill(Theme.gradient)
                                .frame(width: geo.size.width * CGFloat(min(max(ratio, 0), 1)))
                        }
                        .frame(height: 3)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatDuration(track.seconds)).font(.subheadline.weight(.medium)).monospacedDigit()
                    Text("\(track.plays)×").font(.caption).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let source = track.source {
                    if let url = WebLink.track(source: source, key: track.id, title: track.title, artist: track.artist) {
                        openURL(url)
                    }
                } else {
                    tracker.play(id: track.id)
                }
            }

            StarButton(id: track.id, title: track.title, artist: track.artist, source: track.source)
        }
        .contextMenu {
            PlayOnBrowserItems(song: BrowserSong(source: track.source, key: track.id, title: track.title, artist: track.artist))
            AddToPlaylistMenu(track: PlaylistTrack(source: track.source, key: track.id, title: track.title, artist: track.artist))
        }
    }
}

func dayLabel(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "Today" }
    if cal.isDateInYesterday(date) { return "Yesterday" }
    return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
}

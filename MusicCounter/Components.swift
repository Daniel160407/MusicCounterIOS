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

/// The app logo in the middle of the screen, like YouTube's launch, while the other devices' stats are
/// first fetched from Firestore, with a week of service columns swaying beneath it. The logo opens exactly
/// where the launch screen puts it, then glides up as the columns rise so the two sit centred together.
struct SyncSplash: View {
    @EnvironmentObject var sync: Sync
    /// Never holds the app back for long, e.g. when offline.
    @State private var timedOut = false
    @State private var showColumns = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { sync.isLoading && !timedOut }

    var body: some View {
        ZStack {
            if active {
                // The background and logo fade out once the stats are in…
                ZStack {
                    Color(.systemBackground)
                    layout(logo: true)
                }
                .ignoresSafeArea()
                .transition(.opacity)
                .task {
                    if reduceMotion {
                        showColumns = true
                    } else {
                        // One frame on the launch screen's layout first, so the hand-off doesn't jump.
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { showColumns = true }
                    }
                    guard (try? await Task.sleep(nanoseconds: 10_000_000_000)) != nil else { return }
                    timedOut = true
                }
                .onDisappear { showColumns = false }

                // …while the columns, on their own layer laid out the same way, go at once rather than
                // lingering through the fade.
                layout(logo: false)
                    .ignoresSafeArea()
                    .transition(.identity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: active)
        .onChange(of: sync.isLoading) { loading in
            // A later sign-in gets the full wait again.
            if loading { timedOut = false }
        }
    }

    /// The logo with the columns beneath it, centred together on the whole screen as the launch screen's
    /// image is; one layer draws the logo and the other the columns.
    private func layout(logo: Bool) -> some View {
        VStack(spacing: 36) {
            Image("AppLogo").opacity(logo ? 1 : 0)
            if showColumns {
                if logo {
                    SplashColumns().hidden()
                } else {
                    SplashColumns().transition(.opacity)
                }
            }
        }
    }
}

/// Seven day columns, each split into Spotify, YouTube and iPhone, rising in one after another and then
/// rolling in a wave while the services trade shares, as if the week were still being tallied.
private struct SplashColumns: View {
    private static let services = ["spotify", "youtube", "ios"]
    private static let days = ["M", "T", "W", "T", "F", "S", "S"]
    private static let maxHeight: CGFloat = 72

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var risen = false

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSince(start)
            VStack(spacing: 18) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(0..<Self.days.count, id: \.self) { day in
                        VStack(spacing: 6) {
                            column(day: day, t: t)
                                .frame(height: Self.maxHeight, alignment: .bottom)
                            Text(Self.days[day])
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .scaleEffect(x: 1, y: risen ? 1 : 0.01, anchor: .bottom)
                        .opacity(risen ? 1 : 0)
                        .animation(.spring(response: 0.55, dampingFraction: 0.7).delay(Double(day) * 0.07), value: risen)
                    }
                }
                legend(t: t)
                    .opacity(risen ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.5), value: risen)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your listening")
        .onAppear {
            start = Date()
            if reduceMotion { risen = true } else { DispatchQueue.main.async { risen = true } }
        }
    }

    /// How far into its swing a day's column is (0…1): a wave running left to right across the week.
    private func swing(day: Int, t: Double) -> Double {
        reduceMotion ? [0.55, 0.8, 0.45, 1, 0.7, 0.35, 0.6][day] : 0.5 + 0.5 * sin(t * 2.4 - Double(day) * 0.75)
    }

    private func column(day: Int, t: Double) -> some View {
        let lift = swing(day: day, t: t)
        let height = Self.maxHeight * CGFloat(0.3 + 0.7 * lift)
        // Each service's share of the day drifts at its own pace, so the segments slide past one another.
        let weights = Self.services.indices.map { k in
            1.1 + sin(t * (1.1 + Double(k) * 0.35) + Double(day) * 1.3 + Double(k) * 2.1)
        }
        let total = weights.reduce(0, +)
        let gaps = CGFloat(Self.services.count - 1) * 2
        return VStack(spacing: 2) {
            ForEach(Self.services.indices, id: \.self) { k in
                Rectangle()
                    .fill(Service.color(Self.services[k]))
                    .frame(height: max(0, (height - gaps) * CGFloat(weights[k] / total)))
            }
        }
        .frame(width: 14)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        // The crest of the wave catches the light.
        .brightness(0.12 * (lift - 0.5))
        .shadow(color: Service.color(Self.services[day % Self.services.count]).opacity(0.35 * lift), radius: 6 * lift, y: 2)
    }

    /// The three services, their dots pulsing in turn.
    private func legend(t: Double) -> some View {
        HStack(spacing: 14) {
            ForEach(Self.services.indices, id: \.self) { k in
                let pulse = reduceMotion ? 0 : max(0, sin(t * 3 - Double(k) * 1.2))
                HStack(spacing: 5) {
                    Circle()
                        .fill(Service.color(Self.services[k]))
                        .frame(width: 7, height: 7)
                        .scaleEffect(1 + 0.45 * pulse)
                    Text(Service.label(Self.services[k]))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
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

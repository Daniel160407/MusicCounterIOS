import SwiftUI
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
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m" }
    return "\(s)s"
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

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0.001), 1))
                .stroke(Theme.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: progress)
        }
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
    @State private var image: UIImage?

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.gradient.opacity(0.25)
                Image(systemName: "music.note").foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .task(id: id) { load() }
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

struct StarButton: View {
    @EnvironmentObject var store: Store
    let id: String
    let title: String
    let artist: String

    var body: some View {
        let on = store.isFavorite(id)
        Button {
            store.toggleFavorite(id: id, title: title, artist: artist)
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
struct TrackRow: View {
    @EnvironmentObject var tracker: Tracker
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
                ArtworkView(id: track.id, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
            .onTapGesture { tracker.play(id: track.id) }

            StarButton(id: track.id, title: track.title, artist: track.artist)
        }
    }
}

func dayLabel(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "Today" }
    if cal.isDateInYesterday(date) { return "Yesterday" }
    return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
}

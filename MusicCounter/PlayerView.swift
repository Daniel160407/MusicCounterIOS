import SwiftUI
import MediaPlayer
import AVKit

// MARK: - Mini player

/// What the mini player and the full player show: the phone's song while it plays, otherwise a song loaded in
/// the browser extension, otherwise the phone's paused song.
enum MiniPlayerContent {
    case phone(MPMediaItem)
    case browser(RemoteTrack)

    @MainActor init?(tracker: Tracker, sync: Sync) {
        if let item = tracker.nowPlaying, tracker.isPlaying || sync.browserTrack == nil {
            self = .phone(item)
        } else if let track = sync.browserTrack {
            self = .browser(track)
        } else if let item = tracker.nowPlaying {
            self = .phone(item)
        } else {
            return nil
        }
    }

    var key: String {
        switch self {
        case .phone(let item): return "phone:\(item.persistentID)"
        case .browser(let track): return "\(track.deviceID):\(track.source):\(track.id)"
        }
    }
}


/// Floating bar above the tab bar; tap to open the full player.
struct MiniPlayerBar: View {
    @EnvironmentObject var tracker: Tracker
    let item: MPMediaItem
    var open: () -> Void

    var body: some View {
        let id = String(item.persistentID)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ArtworkView(id: id, size: 44)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? "Unknown").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(item.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { haptic(); tracker.previous() } label: {
                    Image(systemName: "backward.fill").font(.title3).frame(width: 40, height: 40)
                }
                .accessibilityLabel("Previous song")
                Button { haptic(); tracker.togglePlayPause() } label: {
                    Image(systemName: tracker.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .contentTransition(.symbolEffectIfAvailable)
                }
                .accessibilityLabel(tracker.isPlaying ? "Pause" : "Play")
                Button { haptic(); tracker.next() } label: {
                    Image(systemName: "forward.fill").font(.title3).frame(width: 40, height: 40)
                }
                .accessibilityLabel("Next song")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            MiniProgress(duration: item.playbackDuration)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        }
        .miniBarBackground()
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .gesture(DragGesture(minimumDistance: 20).onEnded { v in
            if v.translation.height < -30 { open() }
        })
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open player", open)
    }
}

/// The same bar for a song playing in the browser extension. Its buttons press the
/// browser player's own controls through sync; tap it for the full player.
struct BrowserPlayerBar: View {
    @EnvironmentObject var sync: Sync
    let track: RemoteTrack
    var open: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ArtworkView(id: track.key, size: 44, remoteURL: track.thumbnail)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title.isEmpty ? "Unknown" : track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: "desktopcomputer")
                        Text([track.artist, WebLink.label(track.source)].filter { !$0.isEmpty }.joined(separator: " · "))
                    }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                control("backward.fill", "Previous song", .previous)
                control(track.paused ? "play.fill" : "pause.fill", track.paused ? "Play" : "Pause", .playPause)
                control("forward.fill", "Next song", .next)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .miniBarBackground()
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .gesture(DragGesture(minimumDistance: 20).onEnded { v in
            if v.translation.height < -30 { open() }
        })
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playing in \(track.deviceName)")
        .accessibilityAction(named: "Open player", open)
    }

    private func control(_ symbol: String, _ label: String, _ action: BrowserAction) -> some View {
        Button { haptic(); sync.sendBrowserCommand(action) } label: {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 40, height: 40)
                .contentTransition(.symbolEffectIfAvailable)
        }
        .accessibilityLabel(label)
    }
}

private extension View {
    func miniBarBackground() -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

private struct MiniProgress: View {
    @EnvironmentObject var tracker: Tracker
    let duration: TimeInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let ratio = duration > 0 ? tracker.playbackTime / duration : 0
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(Theme.gradient)
                        .frame(width: geo.size.width * CGFloat(min(max(ratio, 0), 1)))
                }
            }
            .frame(height: 3)
        }
    }
}

// MARK: - Full player

struct NowPlayingView: View {
    @EnvironmentObject var tracker: Tracker
    @EnvironmentObject var store: Store
    @EnvironmentObject var sync: Sync
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Follows the mini player, so it switches if the phone starts or stops playing.
        switch MiniPlayerContent(tracker: tracker, sync: sync) {
        case .phone(let item):
            content(item)
        case .browser(let track):
            BrowserNowPlayingView(track: track)
        case nil:
            VStack(spacing: 12) {
                Image(systemName: "music.note").font(.largeTitle).foregroundStyle(Theme.gradient)
                Text("Nothing playing").font(.headline)
                Button("Close") { dismiss() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func content(_ item: MPMediaItem) -> some View {
        let id = String(item.persistentID)
        let title = item.title ?? "Unknown"
        let artist = item.displayArtist

        return GeometryReader { geo in
            let artSide = min(geo.size.width - 48, geo.size.height * 0.42)
            VStack(spacing: 0) {
                Capsule().fill(.white.opacity(0.35)).frame(width: 40, height: 5).padding(.top, 8)

                Spacer(minLength: 12)

                LargeArtwork(item: item)
                    .frame(width: artSide, height: artSide)
                    .scaleEffect(tracker.isPlaying ? 1 : 0.86)
                    .shadow(color: .black.opacity(tracker.isPlaying ? 0.45 : 0.25), radius: tracker.isPlaying ? 30 : 14, y: 14)
                    .animation(.spring(response: 0.45, dampingFraction: 0.7), value: tracker.isPlaying)

                Spacer(minLength: 20)

                VStack(spacing: 22) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.title3.bold()).lineLimit(1)
                            Text(artist).font(.body).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        FavoriteButton(id: id, title: title, artist: artist)
                    }

                    Scrubber(duration: item.playbackDuration)

                    transport

                    VolumeRow()

                    statsAndModes(id: id)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 16))
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .background(PlayerBackground(item: item))
        .preferredColorScheme(.dark)
    }

    private var transport: some View {
        HStack {
            Spacer()
            TransportButton(symbol: "backward.fill", size: 30, label: "Previous") { tracker.previous() }
            Spacer()
            TransportButton(symbol: tracker.isPlaying ? "pause.fill" : "play.fill", size: 46,
                            label: tracker.isPlaying ? "Pause" : "Play") { tracker.togglePlayPause() }
            Spacer()
            TransportButton(symbol: "forward.fill", size: 30, label: "Next") { tracker.next() }
            Spacer()
        }
    }

    private func statsAndModes(id: String) -> some View {
        let stat = store.stats.tracks[id]
        return HStack {
            ModeButton(symbol: "shuffle", on: tracker.shuffleOn, label: "Shuffle") { tracker.toggleShuffle() }
            Spacer()
            VStack(spacing: 2) {
                Text(stat.map { formatDuration($0.seconds) } ?? "0s")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                Text("\(stat?.plays ?? 0) plays counted")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            .accessibilityElement(children: .combine)
            Spacer()
            HStack(spacing: 4) {
                ModeButton(symbol: tracker.repeatMode == .one ? "repeat.1" : "repeat",
                           on: tracker.repeatMode != .none,
                           label: tracker.repeatMode == .one ? "Repeat one" : "Repeat") { tracker.cycleRepeat() }
                AirPlayButton().frame(width: 36, height: 36)
            }
        }
    }
}

/// The full player for a song loaded in the browser extension: same layout as the phone's,
/// plus the browser player's volume, without what only the phone's own player has (seeking,
/// shuffle, repeat, AirPlay).
private struct BrowserNowPlayingView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var sync: Sync
    let track: RemoteTrack

    var body: some View {
        let title = track.title.isEmpty ? "Unknown" : track.title
        GeometryReader { geo in
            let artSide = min(geo.size.width - 48, geo.size.height * 0.42)
            VStack(spacing: 0) {
                Capsule().fill(.white.opacity(0.35)).frame(width: 40, height: 5).padding(.top, 8)

                Spacer(minLength: 12)

                RemoteArtwork(url: track.thumbnail)
                    .frame(width: artSide, height: artSide)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .scaleEffect(track.paused ? 0.86 : 1)
                    .shadow(color: .black.opacity(track.paused ? 0.25 : 0.45), radius: track.paused ? 14 : 30, y: 14)
                    .animation(.spring(response: 0.45, dampingFraction: 0.7), value: track.paused)
                    .accessibilityHidden(true)

                Spacer(minLength: 20)

                VStack(spacing: 22) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.title3.bold()).lineLimit(1)
                            Text(track.artist.isEmpty ? WebLink.label(track.source) : track.artist)
                                .font(.body).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        FavoriteButton(id: track.key, title: title, artist: track.artist, source: track.source)
                    }

                    Label("Playing in \(track.deviceName) · \(WebLink.label(track.source))", systemImage: "desktopcomputer")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.white.opacity(0.12)))

                    HStack {
                        Spacer()
                        TransportButton(symbol: "backward.fill", size: 30, label: "Previous") { sync.sendBrowserCommand(.previous) }
                        Spacer()
                        TransportButton(symbol: track.paused ? "play.fill" : "pause.fill", size: 46,
                                        label: track.paused ? "Play" : "Pause") { sync.sendBrowserCommand(.playPause) }
                        Spacer()
                        TransportButton(symbol: "forward.fill", size: 30, label: "Next") { sync.sendBrowserCommand(.next) }
                        Spacer()
                    }

                    if let volume = track.volume {
                        VStack(spacing: 4) {
                            BrowserVolumeRow(volume: volume, maxVolume: track.maxVolume) { sync.setBrowserVolume($0) }
                            if track.maxVolume <= 1 {
                                Text("\(WebLink.label(track.source)) can't be boosted past 100%")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }

                    let stat = store.remoteTracks[track.key]
                    VStack(spacing: 2) {
                        Text(stat.map { formatDuration($0.seconds) } ?? "0s")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                        Text("\(stat?.plays ?? 0) plays counted")
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                    .accessibilityElement(children: .combine)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 16))
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .background {
            ZStack {
                Color(red: 0.08, green: 0.07, blue: 0.1)
                RemoteArtwork(url: track.thumbnail)
                    .blur(radius: 60).saturation(1.4).opacity(0.85)
                LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Pieces

/// A browser track's cover from the web, or the app's gradient while it loads or if it has none.
private struct RemoteArtwork: View {
    let url: URL?

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Theme.gradient
                    Image(systemName: "music.note")
                        .font(.system(size: geo.size.width * 0.3, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

private struct LargeArtwork: View {
    let item: MPMediaItem

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = item.artwork?.image(at: CGSize(width: geo.size.width * 2, height: geo.size.height * 2)) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Theme.gradient
                    Image(systemName: "music.note")
                        .font(.system(size: geo.size.width * 0.3, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}

/// Blurred, darkened artwork filling the screen behind the player.
private struct PlayerBackground: View {
    let item: MPMediaItem

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.07, blue: 0.1)
            if let image = item.artwork?.image(at: CGSize(width: 200, height: 200)) {
                Image(uiImage: image).resizable().scaledToFill()
                    .blur(radius: 60).saturation(1.4).opacity(0.85)
            } else {
                Theme.gradient.opacity(0.55).blur(radius: 40)
            }
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: item.persistentID)
    }
}

/// Draggable progress bar; the thumb grows while dragging and the time labels follow the finger.
private struct Scrubber: View {
    @EnvironmentObject var tracker: Tracker
    let duration: TimeInterval
    @State private var dragValue: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let current = dragValue ?? tracker.playbackTime
            let ratio = duration > 0 ? min(max(current / duration, 0), 1) : 0
            VStack(spacing: 6) {
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.22))
                        Capsule().fill(.white).frame(width: w * ratio)
                    }
                    .frame(height: dragValue == nil ? 6 : 10)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard duration > 0 else { return }
                            dragValue = Double(min(max(v.location.x / w, 0), 1)) * duration
                        }
                        .onEnded { _ in
                            if let t = dragValue { tracker.seek(to: t) }
                            haptic()
                            dragValue = nil
                        })
                }
                .frame(height: 22)
                .animation(.easeOut(duration: 0.15), value: dragValue == nil)

                HStack {
                    Text(timeString(current))
                    Spacer()
                    Text("-" + timeString(max(duration - current, 0)))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(dragValue == nil ? 0.6 : 0.95))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(timeString(tracker.playbackTime)) of \(timeString(duration))")
        .accessibilityAdjustableAction { dir in
            let step: TimeInterval = dir == .increment ? 15 : -15
            tracker.seek(to: min(tracker.playbackTime + step, duration))
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    let label: String
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button { haptic(); action() } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size * 1.8, height: size * 1.8)
                .background(Circle().fill(.white.opacity(pressed ? 0.15 : 0)))
                .scaleEffect(pressed ? 0.88 : 1)
                .contentTransition(.symbolEffectIfAvailable)
        }
        .buttonStyle(PressStyle(pressed: $pressed))
        .accessibilityLabel(label)
    }
}

private struct PressStyle: ButtonStyle {
    @Binding var pressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { p in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { pressed = p }
            }
    }
}

private struct ModeButton: View {
    let symbol: String
    let on: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button { haptic(); action() } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(on ? Color.black : Color.white.opacity(0.7))
                .frame(width: 36, height: 36)
                .background(Circle().fill(on ? Color.white : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(on ? "On" : "Off")
    }
}

private struct FavoriteButton: View {
    @EnvironmentObject var store: Store
    let id: String
    let title: String
    let artist: String
    /// The service for a browser track; nil for a library song.
    var source: String? = nil
    @State private var bounce = false

    var body: some View {
        let on = store.isFavorite(id)
        Button {
            haptic()
            store.toggleFavorite(id: id, title: title, artist: artist, source: source)
            bounce = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.12)) { bounce = false }
        } label: {
            Image(systemName: on ? "star.fill" : "star")
                .font(.title3.weight(.semibold))
                .foregroundStyle(on ? Color.yellow : Color.white.opacity(0.8))
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white.opacity(0.12)))
                .scaleEffect(bounce ? 1.25 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Remove from favorites" : "Add to favorites")
    }
}

private struct VolumeRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.caption)
            SystemVolumeSlider().frame(height: 34)
            Image(systemName: "speaker.wave.3.fill").font(.caption)
        }
        .foregroundStyle(.white.opacity(0.6))
    }
}

/// The browser player's volume. Where the extension can boost the page, 100% sits in the
/// middle and the right half goes up to 200%. Dragging only moves the slider; letting go
/// sends the level, since the extension picks up one change every few seconds anyway.
private struct BrowserVolumeRow: View {
    let volume: Double
    let maxVolume: Double
    let send: (Double) -> Void
    @State private var value: Double = 0
    @State private var editing = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.caption)
            Slider(value: $value, in: 0...maxVolume) { isEditing in
                editing = isEditing
                guard !isEditing else { return }
                // Easy to land back on the player's own 100%.
                if maxVolume > 1, abs(value - 1) < 0.05 { value = 1 }
                send(value)
            }
            .tint(value > 1 ? .orange : .white)
            .accessibilityLabel("Browser volume")
            .accessibilityValue("\(Int((value * 100).rounded())) percent")
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.weight(.semibold)).monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
        .foregroundStyle(.white.opacity(0.6))
        .onAppear { value = volume }
        .onChange(of: volume) { new in if !editing { value = new } }
    }
}

/// The system volume slider (only moves real volume on a device).
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = .white
        view.setVolumeThumbImage(UIImage(), for: .normal)
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor.white.withAlphaComponent(0.7)
        view.activeTintColor = .white
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

func haptic() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

extension ContentTransition {
    /// Symbol replace animation on iOS 17+, plain swap on iOS 16.
    static var symbolEffectIfAvailable: ContentTransition {
        if #available(iOS 17.0, *) { return .symbolEffect(.replace) }
        return .identity
    }
}

import Foundation
import MediaPlayer

/// Counts listening two ways:
///  1. Live: while the app is running, watches the system Music player and accrues real seconds.
///  2. Reconcile: on launch / foreground, compares the library's playCount against the last
///     snapshot and credits plays that happened while the app was closed (estimated time).
@MainActor
final class Tracker: ObservableObject {
    @Published var authorized = false
    @Published var nowPlaying: MPMediaItem?
    @Published var isPlaying = false
    @Published var shuffleOn = false
    @Published var repeatMode: MPMusicRepeatMode = .none

    private let store: Store
    private let player = MPMusicPlayerController.systemMusicPlayer
    private var timer: Timer?
    private var lastTick = Date()

    // Progress for the song currently playing (half-song rule).
    private var currentID: String?
    private var progress: Double = 0
    private var awarded = false
    private var lastPlaybackTime: TimeInterval = 0
    private var currentDuration: TimeInterval = 0

    init(store: Store) {
        self.store = store
    }

    func start() {
        MPMediaLibrary.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.authorized = status == .authorized
                guard self.authorized else { return }
                self.reconcile()
                self.beginLive()
            }
        }
    }

    // MARK: - Live

    private func beginLive() {
        guard timer == nil else { return }
        player.beginGeneratingPlaybackNotifications()
        let nc = NotificationCenter.default
        nc.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshNowPlaying() }
        }
        nc.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: player, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshNowPlaying() }
        }
        lastTick = Date()
        refreshNowPlaying()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Back in the foreground: the player may have moved on while iOS had the app suspended
    /// (e.g. songs advancing on the lock screen), and its notifications aren't replayed.
    func becameActive() {
        if timer != nil { refreshNowPlaying() }
        reconcile()
    }

    /// Seconds the app couldn't watch the player (suspended in the background); 0 while it runs.
    private var unseenTime: TimeInterval {
        let gap = Date().timeIntervalSince(lastTick) - 1
        return gap > 2 ? gap : 0
    }

    private func refreshNowPlaying(unseen: TimeInterval? = nil) {
        nowPlaying = player.nowPlayingItem
        isPlaying = player.playbackState == .playing
        shuffleOn = player.shuffleMode != .off
        repeatMode = player.repeatMode == .default ? .none : player.repeatMode
        let id = nowPlaying.map { String($0.persistentID) }
        if id != currentID {
            let unseen = unseen ?? unseenTime
            // Left a song that already earned a play before its end, while we were watching:
            // Music won't add to its playCount, so the next reconcile mustn't wait for that.
            if let previous = currentID, awarded, unseen == 0,
               currentDuration > 0, lastPlaybackTime < currentDuration - 5 {
                dropPendingLive(previous)
            }
            currentID = id
            currentDuration = nowPlaying?.playbackDuration ?? 0
            let pos = playbackTime
            // A song that started while the app was suspended is already part way through;
            // that listening counts toward its half, up to the time we couldn't see.
            progress = min(pos, unseen)
            awarded = false
            lastPlaybackTime = pos
        }
    }

    private func dropPendingLive(_ id: String) {
        store.mutate { s in
            guard let n = s.pendingLive[id] else { return }
            if n > 1 { s.pendingLive[id] = n - 1 } else { s.pendingLive[id] = nil }
        }
    }

    private func tick() {
        let unseen = unseenTime
        let now = Date()
        let elapsed = min(now.timeIntervalSince(lastTick), 2)
        lastTick = now

        guard player.playbackState == .playing,
              let item = player.nowPlayingItem,
              !item.isCloudItem else { return }

        let id = String(item.persistentID)
        if id != currentID { refreshNowPlaying(unseen: unseen) }

        // Replayed from the start after earning a play: start a fresh count, including any
        // of the new run that played while the app was suspended (repeat one on the lock screen).
        let pos = playbackTime
        if awarded && pos < lastPlaybackTime - 3 {
            let wrapped = unseen - max(item.playbackDuration - lastPlaybackTime, 0)
            progress = min(pos, max(wrapped, 0))
            awarded = false
        }
        lastPlaybackTime = pos

        let title = item.title ?? "Unknown"
        let artist = item.displayArtist
        store.addTime(elapsed, to: id, title: title, artist: artist)
        progress += elapsed

        // Half-song rule; a flat minute when the length is unknown.
        let threshold = item.playbackDuration > 0 ? item.playbackDuration / 2 : 60
        if !awarded && progress >= threshold {
            awarded = true
            store.addPlays(1, to: id, title: title, artist: artist, on: Date())
            store.mutate { $0.pendingLive[id, default: 0] += 1 }
        }
    }

    // MARK: - Playback controls

    func togglePlayPause() {
        if player.playbackState == .playing { player.pause() } else { player.play() }
        isPlaying = player.playbackState == .playing
    }

    func next() { player.skipToNextItem() }

    func previous() {
        // Like the Music app: restart the song first, go to the previous one on a second press.
        if player.currentPlaybackTime > 3 { player.skipToBeginning() } else { player.skipToPreviousItem() }
    }

    /// Current position in the playing song, read straight from the player.
    var playbackTime: TimeInterval {
        let t = player.currentPlaybackTime
        return t.isFinite ? max(t, 0) : 0
    }

    func seek(to time: TimeInterval) {
        player.currentPlaybackTime = max(time, 0)
        lastPlaybackTime = player.currentPlaybackTime
    }

    func toggleShuffle() {
        player.shuffleMode = shuffleOn ? .off : .songs
        shuffleOn.toggle()
    }

    /// Cycles off → all → one, like the Music app.
    func cycleRepeat() {
        let next: MPMusicRepeatMode
        switch repeatMode {
        case .none: next = .all
        case .all: next = .one
        default: next = .none
        }
        player.repeatMode = next
        repeatMode = next
    }

    /// Plays a song from the library in the system Music player.
    func play(id: String) {
        guard let item = Self.item(id: id) else { return }
        play(queue: [item], startAt: item)
    }

    /// Shuffles every downloaded song by `artist`, including ones whose artist comes from the title.
    func play(artist: String) {
        let items = (MPMediaQuery.songs().items ?? []).filter { $0.displayArtist == artist }
        play(queue: items, shuffle: true)
    }

    /// Replaces the queue with `items` and starts at `startAt` (or the first song, or a random one when shuffling).
    func play(queue items: [MPMediaItem], startAt start: MPMediaItem? = nil, shuffle: Bool = false) {
        let playable = items.filter { !$0.isCloudItem }
        guard !playable.isEmpty else { return }
        player.setQueue(with: MPMediaItemCollection(items: playable))
        player.shuffleMode = shuffle ? .songs : .off
        if let start { player.nowPlayingItem = start }
        player.prepareToPlay()
        player.play()
        refreshNowPlaying()
    }

    static func item(id: String) -> MPMediaItem? {
        guard let pid = UInt64(id) else { return nil }
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: pid), forProperty: MPMediaItemPropertyPersistentID))
        guard let item = query.items?.first, !item.isCloudItem else { return nil }
        return item
    }

    // MARK: - Reconcile with the library

    func reconcile() {
        guard authorized || MPMediaLibrary.authorizationStatus() == .authorized else { return }
        let items = MPMediaQuery.songs().items ?? []
        let firstRun = !store.stats.baselined

        var newSnapshot = store.stats.snapshot
        var pending = store.stats.pendingLive
        let playingID = player.nowPlayingItem.map { String($0.persistentID) }

        for item in items where !item.isCloudItem {
            let id = String(item.persistentID)
            let count = item.playCount
            defer { newSnapshot[id] = count }

            // First run (or a song new to the library): record a baseline, don't credit old history.
            guard !firstRun, let previous = store.stats.snapshot[id] else { continue }

            let delta = count - previous
            guard delta > 0 else {
                // Counted live but skipped before its end, so Music never counted it. Forget it,
                // or it would swallow the next play of this song made with the app closed.
                if id != playingID { pending[id] = nil }
                continue
            }

            let alreadyLive = min(pending[id] ?? 0, delta)
            pending[id] = (pending[id] ?? 0) - alreadyLive
            let missed = delta - alreadyLive
            guard missed > 0 else { continue }

            store.addPlays(
                missed, to: id,
                title: item.title ?? "Unknown",
                artist: item.displayArtist,
                estimatedSeconds: Double(missed) * item.playbackDuration,
                on: item.lastPlayedDate
            )
        }

        store.mutate { s in
            s.snapshot = newSnapshot
            s.pendingLive = pending.filter { $0.value > 0 }
            s.baselined = true
        }
    }
}

extension MPMediaItem {
    /// Artist to show and record; falls back to the "Artist - Song" title prefix.
    var displayArtist: String { ArtistName.resolve(artist, title: title) }
}

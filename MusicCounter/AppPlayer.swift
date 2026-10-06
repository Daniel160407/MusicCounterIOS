import AVFoundation
import MediaPlayer

/// Plays downloaded, unprotected songs (e.g. ones imported from a Mac) inside Music Counter.
/// Unlike the Music app's player, iOS keeps the app running while it plays, so every second
/// and every skip — including ones on the lock screen — is seen and counted live.
@MainActor
final class AppPlayer {
    /// Called whenever the song, play state or modes change.
    var onChange: (() -> Void)?

    private(set) var shuffleOn = false
    private(set) var repeatMode: MPMusicRepeatMode = .none

    private let player = AVPlayer()
    private var queue: [MPMediaItem] = []
    /// Play order, as indices into `queue`; `position` points into it.
    private var order: [Int] = []
    private var position = 0
    private var observers: [NSObjectProtocol] = []
    private var rateObservation: NSKeyValueObservation?
    private var configured = false

    /// Songs with a local, unprotected file. Apple Music downloads and cloud songs are not.
    static func canPlay(_ item: MPMediaItem) -> Bool {
        item.assetURL != nil && !item.hasProtectedAsset && !item.isCloudItem
    }

    var current: MPMediaItem? {
        order.indices.contains(position) ? queue[order[position]] : nil
    }

    var isPlaying: Bool { player.rate != 0 }

    var time: TimeInterval {
        let t = player.currentTime().seconds
        return t.isFinite ? max(t, 0) : 0
    }

    // MARK: - Queue

    /// Replaces the queue and starts at `start` (or the first song, or a random one when shuffling).
    func play(_ items: [MPMediaItem], startAt start: MPMediaItem?, shuffle: Bool) {
        configure()
        queue = items
        shuffleOn = shuffle
        let first = start.flatMap { s in items.firstIndex { $0.persistentID == s.persistentID } }
            ?? (shuffle ? Int.random(in: items.indices) : 0)
        reorder(keeping: first)
        load(play: true)
    }

    func togglePlayPause() {
        if isPlaying { player.pause() } else { resume() }
    }

    func next() {
        guard !order.isEmpty else { return }
        if position + 1 < order.count {
            position += 1
            load(play: isPlaying)
        } else {
            // Past the last song: back to the start, playing on only when repeating.
            position = 0
            load(play: isPlaying && repeatMode == .all)
        }
    }

    func previous() {
        guard !order.isEmpty else { return }
        // Like the Music app: restart the song first, go to the previous one on a second press.
        if time > 3 || (position == 0 && repeatMode != .all) {
            seek(to: 0)
        } else {
            position = position > 0 ? position - 1 : order.count - 1
            load(play: isPlaying)
        }
    }

    func seek(to seconds: TimeInterval) {
        player.seek(to: CMTime(seconds: max(seconds, 0), preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in self?.updateNowPlayingInfo() }
        }
    }

    func toggleShuffle() {
        guard let playing = order.indices.contains(position) ? order[position] : nil else {
            shuffleOn.toggle()
            return
        }
        shuffleOn.toggle()
        reorder(keeping: playing)
        onChange?()
    }

    func setRepeat(_ mode: MPMusicRepeatMode) {
        repeatMode = mode
        onChange?()
    }

    /// Stops when the Music app's player takes over.
    func pause() {
        player.pause()
    }

    /// Rebuilds the play order so `index` is the current song: shuffled after it, or in queue order.
    private func reorder(keeping index: Int) {
        if shuffleOn {
            order = [index] + queue.indices.filter { $0 != index }.shuffled()
            position = 0
        } else {
            order = Array(queue.indices)
            position = index
        }
    }

    private func load(play: Bool) {
        guard let item = current, let url = item.assetURL else {
            player.replaceCurrentItem(with: nil)
            onChange?()
            return
        }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        if play { resume() } else { player.pause() }
        updateNowPlayingInfo()
        onChange?()
    }

    private func resume() {
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
    }

    private func finished() {
        if repeatMode == .one {
            player.seek(to: .zero)
            resume()
        } else if position + 1 < order.count {
            position += 1
            load(play: true)
        } else {
            position = 0
            load(play: repeatMode == .all)
        }
    }

    // MARK: - System integration

    private func configure() {
        guard !configured else { return }
        configured = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.finished()
            }
        })
        // A call or another app's audio pauses playback; resume afterwards when iOS says to.
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo
            let type = (info?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = AVAudioSession.InterruptionOptions(rawValue: info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            Task { @MainActor in
                guard let self else { return }
                if type == .ended && options.contains(.shouldResume) { self.resume() }
                self.onChange?()
            }
        })
        // AVPlayer already pauses when headphones are unplugged; just refresh what's shown.
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onChange?() }
        })
        rateObservation = player.observe(\.rate) { [weak self] _, _ in
            Task { @MainActor in
                self?.updateNowPlayingInfo()
                self?.onChange?()
            }
        }

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    /// What the lock screen and Control Center show.
    private func updateNowPlayingInfo() {
        guard let item = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title ?? "Unknown",
            MPMediaItemPropertyArtist: item.displayArtist,
            MPMediaItemPropertyPlaybackDuration: item.playbackDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let album = item.albumTitle { info[MPMediaItemPropertyAlbumTitle] = album }
        if let artwork = item.artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

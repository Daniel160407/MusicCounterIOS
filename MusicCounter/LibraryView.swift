import SwiftUI
import MediaPlayer

/// Browse the on-device library (downloaded songs only) and start playback.
struct LibraryView: View {
    @EnvironmentObject var tracker: Tracker
    @State private var section = 0
    @State private var query = ""
    @State private var songs: [MPMediaItem] = []
    @State private var albums: [MPMediaItemCollection] = []
    @State private var playlists: [LibraryPlaylist] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $section) {
                    Text("Songs").tag(0)
                    Text("Albums").tag(1)
                    Text("Playlists").tag(2)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))

                if !tracker.authorized {
                    emptyState("Library access needed", "lock.fill",
                               "Allow Media & Apple Music access in Settings to browse your songs.")
                } else if loaded && songs.isEmpty {
                    emptyState("No downloaded songs", "music.note",
                               "Songs you add to the Music app (including your own MP3s) appear here.")
                } else if section == 0 {
                    songsSection
                } else if section == 1 {
                    albumsSection
                } else {
                    playlistsSection
                }
            }
            .listStyle(.insetGrouped)
            .pageBottomMargin()
            .searchable(text: $query, prompt: ["Songs or artists", "Albums or artists", "Playlists"][section])
            .navigationTitle("Library")
            .task(id: tracker.authorized) { load() }
            .refreshable { load() }
        }
    }

    private var filteredSongs: [MPMediaItem] {
        guard !query.isEmpty else { return songs }
        return songs.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query) ||
            $0.displayArtist.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredAlbums: [MPMediaItemCollection] {
        guard !query.isEmpty else { return albums }
        return albums.filter {
            ($0.representativeItem?.albumTitle ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.representativeItem?.albumArtist ?? $0.representativeItem?.artist ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredPlaylists: [LibraryPlaylist] {
        guard !query.isEmpty else { return playlists }
        return playlists.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder private var playlistsSection: some View {
        let list = filteredPlaylists
        Section {
            if list.isEmpty {
                Text(query.isEmpty ? "No playlists with downloaded songs." : "No matching playlists.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(list) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlist: playlist)
                } label: {
                    HStack(spacing: 12) {
                        PlaylistCover(items: playlist.items, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("\(playlist.items.count) songs").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } footer: {
            Text("Synced live from the Music app. Streamed-only songs that aren't downloaded are left out.")
        }
    }

    @ViewBuilder private var songsSection: some View {
        let list = filteredSongs
        Section {
            PlayShuffleButtons(items: list)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
        Section {
            ForEach(list, id: \.persistentID) { item in
                SongRow(item: item) { tracker.play(queue: list, startAt: item) }
            }
        } footer: {
            if !list.isEmpty { Text("\(list.count) songs") }
        }
    }

    @ViewBuilder private var albumsSection: some View {
        let list = filteredAlbums
        Section {
            ForEach(list, id: \.persistentID) { album in
                NavigationLink {
                    AlbumDetailView(album: album)
                } label: {
                    HStack(spacing: 12) {
                        ArtworkView(id: String(album.representativeItem?.persistentID ?? 0), size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(album.representativeItem?.albumTitle ?? "Unknown album")
                                .font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(album.representativeItem?.albumArtist ?? album.representativeItem?.artist ?? "Unknown artist")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func emptyState(_ title: String, _ icon: String, _ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(Theme.gradient)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
    }

    private func load() {
        guard MPMediaLibrary.authorizationStatus() == .authorized else { return }
        songs = (MPMediaQuery.songs().items ?? [])
            .filter { !$0.isCloudItem }
            .sorted { ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending }
        albums = (MPMediaQuery.albums().collections ?? [])
            .map { MPMediaItemCollection(items: $0.items.filter { !$0.isCloudItem }) }
            .filter { !$0.items.isEmpty }
            .sorted {
                ($0.representativeItem?.albumTitle ?? "")
                    .localizedCaseInsensitiveCompare($1.representativeItem?.albumTitle ?? "") == .orderedAscending
            }
        playlists = (MPMediaQuery.playlists().collections as? [MPMediaPlaylist] ?? [])
            .compactMap { pl in
                let items = pl.items.filter { !$0.isCloudItem }
                guard !items.isEmpty else { return nil }
                return LibraryPlaylist(id: pl.persistentID, name: pl.name ?? "Untitled playlist", items: items)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        loaded = true
    }
}

struct LibraryPlaylist: Identifiable {
    let id: MPMediaEntityPersistentID
    let name: String
    let items: [MPMediaItem]
}

/// A 2×2 grid of the first distinct album covers, or a single cover for small playlists.
private struct PlaylistCover: View {
    let items: [MPMediaItem]
    var size: CGFloat

    var body: some View {
        var seen = Set<MPMediaEntityPersistentID>()
        let covers = items.filter { seen.insert($0.albumPersistentID).inserted }.prefix(4).map { String($0.persistentID) }
        return Group {
            if covers.count == 4 {
                VStack(spacing: 0) {
                    HStack(spacing: 0) { tile(covers[0]); tile(covers[1]) }
                    HStack(spacing: 0) { tile(covers[2]); tile(covers[3]) }
                }
            } else {
                ArtworkView(id: covers.first ?? "0", size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
    }

    private func tile(_ id: String) -> some View {
        ArtworkView(id: id, size: size / 2).clipShape(Rectangle())
    }
}

private struct PlaylistDetailView: View {
    @EnvironmentObject var tracker: Tracker
    let playlist: LibraryPlaylist
    @State private var query = ""

    /// Matches title, artist or album; the playlist order is kept.
    private var filteredItems: [MPMediaItem] {
        guard !query.isEmpty else { return playlist.items }
        return playlist.items.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query) ||
            $0.displayArtist.localizedCaseInsensitiveContains(query) ||
            ($0.albumTitle ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let items = playlist.items
        let list = filteredItems
        List {
            if query.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        PlaylistCover(items: items, size: 200)
                            .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                        VStack(spacing: 4) {
                            Text(playlist.name).font(.title3.bold()).multilineTextAlignment(.center)
                            Text("\(items.count) songs · \(formatDuration(items.reduce(0) { $0 + $1.playbackDuration }))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        PlayShuffleButtons(items: items)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            Section {
                if list.isEmpty {
                    Text("No matching songs in this playlist.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                // Tapping a result still plays the whole playlist, starting from that song.
                ForEach(list, id: \.persistentID) { item in
                    SongRow(item: item) { tracker.play(queue: items, startAt: item) }
                }
            } footer: {
                if !query.isEmpty && !list.isEmpty { Text("\(list.count) of \(items.count) songs") }
            }
        }
        .listStyle(.insetGrouped)
        .pageBottomMargin()
        .searchable(text: $query, prompt: "Search in \(playlist.name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AlbumDetailView: View {
    @EnvironmentObject var tracker: Tracker
    let album: MPMediaItemCollection

    var body: some View {
        let rep = album.representativeItem
        let items = album.items.sorted { $0.albumTrackNumber < $1.albumTrackNumber }
        List {
            Section {
                VStack(spacing: 12) {
                    ArtworkView(id: String(rep?.persistentID ?? 0), size: 200)
                        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                    VStack(spacing: 4) {
                        Text(rep?.albumTitle ?? "Unknown album").font(.title3.bold()).multilineTextAlignment(.center)
                        Text(rep?.albumArtist ?? rep?.artist ?? "Unknown artist")
                            .font(.body).foregroundStyle(Theme.accent)
                        Text("\(items.count) songs · \(formatDuration(items.reduce(0) { $0 + $1.playbackDuration }))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    PlayShuffleButtons(items: items)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(items, id: \.persistentID) { item in
                    SongRow(item: item, trackNumber: item.albumTrackNumber) {
                        tracker.play(queue: items, startAt: item)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .pageBottomMargin()
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlayShuffleButtons: View {
    @EnvironmentObject var tracker: Tracker
    let items: [MPMediaItem]

    var body: some View {
        HStack(spacing: 12) {
            button("Play", "play.fill") { tracker.play(queue: items) }
            button("Shuffle", "shuffle") { tracker.play(queue: items, startAt: items.randomElement(), shuffle: true) }
        }
        .disabled(items.isEmpty)
    }

    private func button(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button { haptic(); action() } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(Theme.accent)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A library song; the playing one shows an equalizer and accent-colored title.
private struct SongRow: View {
    @EnvironmentObject var tracker: Tracker
    @EnvironmentObject var store: Store
    let item: MPMediaItem
    var trackNumber: Int? = nil
    let play: () -> Void

    var body: some View {
        let id = String(item.persistentID)
        let current = tracker.nowPlaying?.persistentID == item.persistentID
        Button(action: play) {
            HStack(spacing: 12) {
                if let trackNumber {
                    ZStack {
                        if current { EqualizerView(active: tracker.isPlaying).scaleEffect(0.6) }
                        else { Text(trackNumber > 0 ? "\(trackNumber)" : "–").foregroundStyle(.secondary) }
                    }
                    .font(.subheadline.monospacedDigit())
                    .frame(width: 24)
                } else {
                    ZStack {
                        ArtworkView(id: id, size: 44)
                        if current {
                            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.45))
                            EqualizerView(active: tracker.isPlaying).scaleEffect(0.6)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title ?? "Unknown")
                        .font(.subheadline.weight(current ? .semibold : .regular))
                        .foregroundStyle(current ? Theme.accent : .primary)
                        .lineLimit(1)
                    Text(item.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let plays = store.stats.tracks[id]?.plays, plays > 0 {
                    Text("\(plays)×").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button {
                store.toggleFavorite(id: id, title: item.title ?? "Unknown", artist: item.displayArtist)
            } label: {
                Label("Favorite", systemImage: store.isFavorite(id) ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
        .accessibilityHint("Plays this song")
    }
}

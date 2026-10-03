import SwiftUI
import MediaPlayer

/// Browse the on-device library (downloaded songs only) and start playback.
struct LibraryView: View {
    @EnvironmentObject var tracker: Tracker
    @State private var section = 0
    @State private var query = ""
    @State private var songs: [MPMediaItem] = []
    @State private var playlists: [LibraryPlaylist] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $section) {
                    Text("Songs").tag(0)
                    Text("Playlists").tag(1)
                    Text("Recents").tag(2)
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
                } else if section == 2 {
                    recentsSection
                } else {
                    playlistsSection
                }
            }
            .listStyle(.insetGrouped)
            .pageBottomMargin()
            .searchable(text: $query, prompt: ["Songs or artists", "Playlists", "Songs or artists"][section])
            .navigationTitle("Library")
            .task(id: tracker.authorized) { load() }
            .refreshable { load() }
            // Picks up songs added to playlists here or in the Music app.
            .onReceive(NotificationCenter.default.publisher(for: .MPMediaLibraryDidChange).receive(on: DispatchQueue.main)) { _ in
                load()
            }
        }
    }

    private var filteredSongs: [MPMediaItem] {
        guard !query.isEmpty else { return songs }
        return songs.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query) ||
            $0.displayArtist.localizedCaseInsensitiveContains(query)
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

    /// Newest additions first, capped so a big library stays quick to scroll.
    private var recentSongs: [MPMediaItem] {
        Array(songs.sorted { $0.dateAdded > $1.dateAdded }.prefix(100))
    }

    @ViewBuilder private var recentsSection: some View {
        let recent = recentSongs
        let list = query.isEmpty ? recent : recent.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query) ||
            $0.displayArtist.localizedCaseInsensitiveContains(query)
        }
        Section {
            PlayShuffleButtons(items: list)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
        if list.isEmpty {
            Section {
                Text("No matching songs.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        ForEach(recentGroups(list), id: \.title) { group in
            Section(group.title) {
                ForEach(group.items, id: \.persistentID) { item in
                    SongRow(item: item) { tracker.play(queue: list, startAt: item) }
                }
            }
        }
        if !list.isEmpty {
            Section {} footer: {
                Text("The \(recent.count) most recently downloaded or added songs, newest first.")
            }
        }
    }

    /// Buckets songs (already newest first) by when they were added.
    private func recentGroups(_ items: [MPMediaItem]) -> [(title: String, items: [MPMediaItem])] {
        let cal = Calendar.current
        let now = Date()
        func bucket(_ date: Date) -> String {
            if cal.isDateInToday(date) { return "Today" }
            if cal.isDateInYesterday(date) { return "Yesterday" }
            if let days = cal.dateComponents([.day], from: date, to: now).day {
                if days < 7 { return "This Week" }
                if days < 30 { return "This Month" }
            }
            return "Earlier"
        }
        var groups: [(title: String, items: [MPMediaItem])] = []
        for item in items {
            let title = bucket(item.dateAdded)
            if groups.last?.title == title { groups[groups.count - 1].items.append(item) }
            else { groups.append((title, [item])) }
        }
        return groups
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
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
        songs = (MPMediaQuery.songs().items ?? [])
            .filter { !$0.isCloudItem }
            .sorted { ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending }
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
    @State private var pickingSongs = false

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
                        Button { haptic(); pickingSongs = true } label: {
                            Label("Add Songs", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(Theme.accent)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
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
        .toolbar { AddToPlaylistButton(items: playlist.items) }
        .sheet(isPresented: $pickingSongs) { SongPickerSheet(playlist: playlist) }
    }
}

/// Library songs with checkboxes for choosing what goes into a playlist. Songs already in it
/// stay checked and locked: the iOS media library has no way for apps to remove songs.
private struct SongPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let playlist: LibraryPlaylist
    @State private var songs: [MPMediaItem] = []
    @State private var selected = Set<MPMediaEntityPersistentID>()
    @State private var query = ""
    @State private var busy = false
    @State private var error: String?

    private var existing: Set<MPMediaEntityPersistentID> { Set(playlist.items.map(\.persistentID)) }

    private var filteredSongs: [MPMediaItem] {
        guard !query.isEmpty else { return songs }
        return songs.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query) ||
            $0.displayArtist.localizedCaseInsensitiveContains(query) ||
            ($0.albumTitle ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let existing = existing
        let list = filteredSongs
        NavigationStack {
            List {
                Section {
                    if list.isEmpty {
                        Text(query.isEmpty ? "No downloaded songs." : "No matching songs.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(list, id: \.persistentID) { item in
                        let inPlaylist = existing.contains(item.persistentID)
                        let checked = inPlaylist || selected.contains(item.persistentID)
                        Button { toggle(item) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(checked ? Theme.accent : Color.secondary)
                                    .opacity(inPlaylist ? 0.5 : 1)
                                ArtworkView(id: String(item.persistentID), size: 40)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title ?? "Unknown").font(.subheadline).lineLimit(1)
                                    Text(inPlaylist ? "Already in playlist" : item.displayArtist)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(inPlaylist || busy)
                        .accessibilityAddTraits(checked ? .isSelected : [])
                    }
                } footer: {
                    if !songs.isEmpty { Text("\(selected.count) selected · \(existing.count) already in playlist") }
                }
            }
            .listStyle(.insetGrouped)
            .overlay { if busy { ProgressView() } }
            .searchable(text: $query, prompt: "Songs, artists or albums")
            .navigationTitle("Add to \(playlist.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Add" : "Add \(selected.count)") { add() }
                        .disabled(selected.isEmpty || busy)
                }
            }
            .alert("Couldn't add to playlist", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
            .task { load() }
        }
    }

    private func load() {
        songs = (MPMediaQuery.songs().items ?? [])
            .filter { !$0.isCloudItem }
            .sorted { ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending }
    }

    private func toggle(_ item: MPMediaItem) {
        if selected.remove(item.persistentID) == nil { selected.insert(item.persistentID) }
    }

    /// Adds in library (title) order, after the songs already in the playlist.
    private func add() {
        let query = MPMediaQuery.playlists()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: playlist.id, forProperty: MPMediaPlaylistPropertyPersistentID))
        guard let target = query.collections?.first as? MPMediaPlaylist else {
            error = "This playlist is no longer in your library."
            return
        }
        busy = true
        target.add(songs.filter { selected.contains($0.persistentID) }) { error in
            DispatchQueue.main.async {
                busy = false
                if let error { self.error = playlistErrorMessage(error); return }
                haptic()
                dismiss()
            }
        }
    }
}

/// Explains a failed playlist change; iOS refuses edits to playlists made in the Music app.
private func playlistErrorMessage(_ error: Error?) -> String {
    if let error = error as? MPError, error.code == .permissionDenied {
        return "iOS only lets Music Counter change playlists it created. Make a new playlist here, or add the song in the Music app."
    }
    return error?.localizedDescription ?? "Something went wrong. Try again."
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
    let play: () -> Void
    @State private var addingToPlaylist = false

    var body: some View {
        let id = String(item.persistentID)
        let current = tracker.nowPlaying?.persistentID == item.persistentID
        Button(action: play) {
            HStack(spacing: 12) {
                ZStack {
                    ArtworkView(id: id, size: 44)
                    if current {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.45))
                        EqualizerView(active: tracker.isPlaying).scaleEffect(0.6)
                    }
                }
                .frame(width: 44, height: 44)
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
        .swipeActions(edge: .trailing) {
            Button { addingToPlaylist = true } label: {
                Label("Add to Playlist", systemImage: "text.badge.plus")
            }
            .tint(Theme.accent)
        }
        .contextMenu {
            PlayOnBrowserItems(song: BrowserSong(source: nil, key: id, title: item.title ?? "Unknown", artist: item.displayArtist))
            Button { addingToPlaylist = true } label: {
                Label("Add to Playlist…", systemImage: "text.badge.plus")
            }
            Button {
                store.toggleFavorite(id: id, title: item.title ?? "Unknown", artist: item.displayArtist)
            } label: {
                if store.isFavorite(id) { Label("Unfavorite", systemImage: "star.slash") }
                else { Label("Favorite", systemImage: "star") }
            }
        }
        .sheet(isPresented: $addingToPlaylist) { AddToPlaylistSheet(items: [item]) }
        .accessibilityHint("Plays this song")
    }
}

/// Toolbar button that adds every song on the screen (a playlist) to a playlist.
private struct AddToPlaylistButton: ToolbarContent {
    let items: [MPMediaItem]
    @State private var adding = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { adding = true } label: {
                Label("Add to Playlist", systemImage: "text.badge.plus")
            }
            .disabled(items.isEmpty)
            .sheet(isPresented: $adding) { AddToPlaylistSheet(items: items) }
        }
    }
}

/// Picks a playlist to add songs to, or makes a new one. Songs already in the playlist are
/// skipped so nothing is duplicated. iOS only lets an app change playlists it created itself,
/// so adding to one made in the Music app explains that instead of failing silently.
private struct AddToPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    let items: [MPMediaItem]
    @State private var playlists: [MPMediaPlaylist] = []
    @State private var busy = false
    @State private var naming = false
    @State private var newName = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { newName = ""; naming = true } label: {
                        Label("New Playlist…", systemImage: "plus")
                    }
                    .disabled(busy)
                }
                if !playlists.isEmpty {
                    Section("Playlists") {
                        ForEach(playlists, id: \.persistentID) { playlist in
                            let added = missing(from: playlist).isEmpty
                            Button { add(missing(from: playlist), to: playlist) } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(playlist.name ?? "Untitled playlist")
                                            .font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                                        Text("\(playlist.count) songs").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if added { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(added || busy)
                            .accessibilityValue(added ? "Already added" : "")
                        }
                    }
                }
            }
            .overlay { if busy { ProgressView() } }
            .navigationTitle(items.count == 1 ? "Add to Playlist" : "Add \(items.count) Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("New Playlist", isPresented: $naming) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { create() }
            }
            .alert("Couldn't add to playlist", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
            .task { load() }
        }
        .presentationDetents([.medium, .large])
    }

    /// Regular playlists only; smart and Genius playlists can't be edited.
    private func load() {
        playlists = (MPMediaQuery.playlists().collections as? [MPMediaPlaylist] ?? [])
            .filter { $0.playlistAttributes.isDisjoint(with: [.smart, .genius]) }
            .sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
    }

    private func missing(from playlist: MPMediaPlaylist) -> [MPMediaItem] {
        let have = Set(playlist.items.map(\.persistentID))
        return items.filter { !have.contains($0.persistentID) }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = MPMediaPlaylistCreationMetadata(name: name.isEmpty ? "New Playlist" : name)
        busy = true
        MPMediaLibrary.default().getPlaylist(with: UUID(), creationMetadata: metadata) { playlist, error in
            DispatchQueue.main.async {
                if let playlist { add(items, to: playlist) } else { fail(error) }
            }
        }
    }

    private func add(_ songs: [MPMediaItem], to playlist: MPMediaPlaylist) {
        busy = true
        playlist.add(songs) { error in
            DispatchQueue.main.async {
                if let error { fail(error); return }
                busy = false
                haptic()
                dismiss()
            }
        }
    }

    private func fail(_ error: Error?) {
        busy = false
        self.error = playlistErrorMessage(error)
    }
}

import SwiftUI

/// Playlists mixing YouTube, YouTube Music and Spotify songs, shared with the extension,
/// as their own section of Library → Playlists, below the downloaded ones. The phone can't
/// play YouTube or Spotify itself, so a playlist is played on a signed-in browser: it opens
/// each song in its service's tab and starts the next when it finishes.
struct BrowserPlaylistsSection: View {
    @EnvironmentObject var sync: Sync
    let query: String

    private var shown: [WebPlaylist] {
        guard !query.isEmpty else { return sync.playlists }
        return sync.playlists.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Section {
            if sync.email == nil {
                Text("Sign in on the Today tab to make playlists of YouTube and Spotify songs that play one after another in your browser.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                let list = shown
                if list.isEmpty && !query.isEmpty {
                    Text("No matching playlists.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(list) { playlist in
                    NavigationLink {
                        WebPlaylistView(id: playlist.id)
                    } label: {
                        PlaylistSummaryRow(playlist: playlist, progress: progress(of: playlist))
                    }
                }
                Button {
                    sync.newPlaylist = NewPlaylistRequest(track: nil)
                } label: {
                    Label("New Playlist", systemImage: "plus")
                }
                .font(.subheadline.weight(.semibold))
                .disabled(sync.playlists.count >= WebPlaylist.maxPlaylists)
            }
        } header: {
            Text("YouTube & Spotify")
        } footer: {
            if sync.email != nil {
                Text("Played in your browser: each song opens in its own service's tab, and the next starts when it finishes. Add songs from any song's long-press menu in Tracks or History, or paste a link.")
            }
        }
    }

    private func progress(of playlist: WebPlaylist) -> PlaylistProgress? {
        sync.browserTrack?.playlist.flatMap { $0.id == playlist.id ? $0 : nil }
    }
}

private struct PlaylistSummaryRow: View {
    let playlist: WebPlaylist
    let progress: PlaylistProgress?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Theme.gradient.opacity(0.25)
                Image(systemName: progress == nil ? "music.note.list" : "waveform").foregroundStyle(Theme.accent)
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(progress.map { "Playing \(min($0.index + 1, $0.count)) of \($0.count)" } ?? songCount(playlist.tracks.count))
                    HStack(spacing: 3) {
                        ForEach(playlist.services, id: \.self) { source in
                            Circle().fill(Service.color(source)).frame(width: 6, height: 6)
                        }
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

func songCount(_ count: Int) -> String { "\(count) \(count == 1 ? "song" : "songs")" }

/// One playlist: its songs in order, reorderable and removable, a field for pasting a
/// link, and buttons that start it on a browser.
struct WebPlaylistView: View {
    @EnvironmentObject var sync: Sync
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var link = ""
    @State private var linkNote: String?
    @State private var resolving = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    var body: some View {
        if let playlist = sync.playlists.first(where: { $0.id == id }) {
            content(playlist)
        } else {
            // Deleted here or on another device.
            Text("This playlist was deleted.").foregroundStyle(.secondary)
        }
    }

    private func content(_ playlist: WebPlaylist) -> some View {
        let progress = sync.browserTrack?.playlist.flatMap { $0.id == playlist.id ? $0 : nil }
        return List {
            Section {
                playButtons(playlist)
            } footer: {
                if sync.browsers.isEmpty {
                    Text("Open Chrome with the Music Counter extension, signed in to the same account, to play this playlist there.")
                } else if let progress {
                    Text("Playing in \(sync.browserTrack?.deviceName ?? "your browser") · \(min(progress.index + 1, progress.count)) of \(progress.count)")
                }
            }

            Section {
                HStack {
                    TextField("Paste a YouTube or Spotify song link", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { addLink(to: playlist) }
                    if resolving {
                        ProgressView()
                    } else {
                        Button("Add") { addLink(to: playlist) }
                            .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } footer: {
                if let linkNote { Text(linkNote) }
            }

            Section {
                if playlist.tracks.isEmpty {
                    Text("No songs yet. Long-press any song and choose Add to a Playlist, or paste a link above.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(Array(playlist.tracks.enumerated()), id: \.element.key) { index, track in
                    PlaylistTrackRow(track: track, index: index, current: progress?.index == index)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // The most recently seen browser; the long-press menu offers the others.
                            guard let browser = sync.browsers.first else { return }
                            haptic()
                            sync.play(playlist, from: index, on: browser)
                        }
                        .contextMenu {
                            ForEach(sync.browsers) { browser in
                                Button {
                                    haptic()
                                    sync.play(playlist, from: index, on: browser)
                                } label: {
                                    Label("Play from Here on \(browser.name)", systemImage: "desktopcomputer")
                                }
                            }
                            Button(role: .destructive) {
                                sync.updatePlaylist(playlist.id) { $0.tracks.remove(at: index) }
                            } label: {
                                Label("Remove from Playlist", systemImage: "minus.circle")
                            }
                        }
                }
                .onMove { from, to in sync.updatePlaylist(playlist.id) { $0.tracks.move(fromOffsets: from, toOffset: to) } }
                .onDelete { offsets in sync.updatePlaylist(playlist.id) { $0.tracks.remove(atOffsets: offsets) } }
            } header: {
                Text(playlist.tracks.isEmpty ? "Songs" : songCount(playlist.tracks.count))
            } footer: {
                if !playlist.tracks.isEmpty && !sync.browsers.isEmpty {
                    Text("Tap a song to play the playlist from there.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .pageBottomMargin()
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !playlist.tracks.isEmpty { EditButton() }
                Menu {
                    Button {
                        newName = playlist.name
                        renaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete Playlist", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename Playlist", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { sync.updatePlaylist(playlist.id) { $0.name = newName } }
        }
        .confirmationDialog("Delete \(playlist.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) {
                sync.deletePlaylist(playlist.id)
                dismiss()
            }
        } message: {
            Text("It is removed from every device signed in to this account.")
        }
    }

    @ViewBuilder private func playButtons(_ playlist: WebPlaylist) -> some View {
        if sync.browsers.isEmpty {
            Label("No browser to play on", systemImage: "desktopcomputer")
                .foregroundStyle(.secondary)
        }
        ForEach(sync.browsers) { browser in
            Button {
                haptic()
                sync.play(playlist, on: browser)
            } label: {
                Label("Play on \(browser.name)", systemImage: "play.fill")
                    .font(.body.weight(.semibold))
            }
            .disabled(playlist.tracks.isEmpty)
        }
    }

    private func addLink(to playlist: WebPlaylist) {
        let text = link
        guard !resolving, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard SongLink.parse(text) != nil else {
            linkNote = "Paste a link to a YouTube, YouTube Music or Spotify song."
            return
        }
        resolving = true
        linkNote = "Looking it up…"
        Task {
            let track = await SongLink.resolve(text)
            resolving = false
            guard let track else { return }
            if playlist.contains(track) {
                linkNote = "Already in \(playlist.name)."
            } else if playlist.tracks.count >= WebPlaylist.maxTracks {
                linkNote = "A playlist holds up to \(WebPlaylist.maxTracks) songs."
            } else {
                sync.add(track, to: playlist.id)
                link = ""
                linkNote = "Added \(track.title)."
            }
        }
    }
}

private struct PlaylistTrackRow: View {
    let track: PlaylistTrack
    let index: Int
    let current: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if current {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.accent)
                } else {
                    Text("\(index + 1)").foregroundStyle(.secondary)
                }
            }
            .font(.caption.weight(.bold)).monospacedDigit()
            .frame(width: 22)
            // A library song's cover comes from the media library, the rest from the web.
            ArtworkView(id: track.source == "ios" ? track.id : track.key, size: 42, remoteURL: track.thumbnail)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title.isEmpty ? track.id : track.title)
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                    .foregroundStyle(current ? Theme.accent : Color.primary)
                Text([track.artist, WebLink.label(track.source)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// A context-menu submenu adding a song to one of the playlists, or to a new one.
/// Shows nothing when signed out.
struct AddToPlaylistMenu: View {
    @EnvironmentObject var sync: Sync
    let track: PlaylistTrack

    var body: some View {
        if sync.email != nil {
            Menu {
                ForEach(sync.playlists) { playlist in
                    let has = playlist.contains(track)
                    Button {
                        haptic()
                        sync.add(track, to: playlist.id)
                    } label: {
                        Label(playlist.name, systemImage: has ? "checkmark" : "music.note.list")
                    }
                    .disabled(has)
                }
                Button {
                    sync.newPlaylist = NewPlaylistRequest(track: track)
                } label: {
                    Label("New Playlist…", systemImage: "plus")
                }
                .disabled(sync.playlists.count >= WebPlaylist.maxPlaylists)
            } label: {
                Label("Add to a Playlist", systemImage: "text.badge.plus")
            }
        }
    }
}

/// A request to name a new playlist; `track`, when given, becomes its first song.
struct NewPlaylistRequest: Identifiable {
    let id = UUID()
    let track: PlaylistTrack?
}

/// The "New Playlist" name prompt, shown once at the root for `Sync.newPlaylist`. An alert
/// attached inside a List row or a context menu doesn't reliably appear, so the rows and
/// menus only set the request.
private struct NewPlaylistPrompt: ViewModifier {
    @EnvironmentObject var sync: Sync
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert("New Playlist", isPresented: Binding(
                get: { sync.newPlaylist != nil },
                set: { if !$0 { sync.newPlaylist = nil } }
            ), presenting: sync.newPlaylist) { request in
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    haptic()
                    sync.createPlaylist(named: name, with: request.track)
                }
            } message: { request in
                if let track = request.track {
                    Text("With \(track.title.isEmpty ? track.id : track.title) as its first song.")
                }
            }
            .onChange(of: sync.newPlaylist?.id) { _ in name = "" }
    }
}

extension View {
    func newPlaylistPrompt() -> some View { modifier(NewPlaylistPrompt()) }
}

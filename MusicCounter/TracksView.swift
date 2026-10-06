import SwiftUI

struct TracksView: View {
    @EnvironmentObject var store: Store
    @State private var sortByPlays = false
    @State private var showAllTracks = false
    @State private var showAllArtists = false

    private var tracks: [TrackStat] {
        let all = store.allTracks
        return sortByPlays
            ? all.sorted { ($0.plays, $0.seconds) > ($1.plays, $1.seconds) }
            : all.sorted { $0.seconds > $1.seconds }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    topTracksCard
                    favoritesCard
                    artistsCard
                }
                .padding(.horizontal, 16)
            }
            .pageBottomMargin()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tracks")
        }
    }

    private var topTracksCard: some View {
        let sorted = tracks
        let shown = showAllTracks ? Array(sorted.prefix(100)) : Array(sorted.prefix(10))
        let maxValue = sortByPlays ? Double(sorted.first?.plays ?? 1) : (sorted.first?.seconds ?? 1)

        return Card(title: "Top tracks") {
            Picker("Sort", selection: $sortByPlays) {
                Text("Time").tag(false)
                Text("Plays").tag(true)
            }
            .pickerStyle(.segmented)

            if shown.isEmpty {
                Text("Play some music from your library and it will show up here.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            ForEach(Array(shown.enumerated()), id: \.element.id) { index, t in
                let value = sortByPlays ? Double(t.plays) : t.seconds
                TrackRow(track: t, rank: index + 1, ratio: maxValue > 0 ? value / maxValue : 0)
            }

            if sorted.count > 10 {
                Button(showAllTracks ? "Show less" : "Show more") {
                    withAnimation { showAllTracks.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var favoritesCard: some View {
        let favs = store.favoriteTracks
        return Card(title: "Favorites") {
            if favs.isEmpty {
                Text("Tap the star on a song to keep it here. Favorites survive Reset.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(favs) { t in
                TrackRow(track: t)
            }
        }
    }

    private var artistsCard: some View {
        let all = store.artists
        let shown = showAllArtists ? Array(all.prefix(100)) : Array(all.prefix(5))
        let maxSeconds = all.first?.seconds ?? 1
        return Card(title: "Top artists") {
            if shown.isEmpty {
                Text("No artists yet.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(shown.enumerated()), id: \.element.name) { index, a in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(a.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        GeometryReader { geo in
                            Capsule().fill(Theme.gradient)
                                .frame(width: geo.size.width * CGFloat(maxSeconds > 0 ? a.seconds / maxSeconds : 0))
                        }
                        .frame(height: 3)
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatDuration(a.seconds)).font(.subheadline.weight(.medium)).monospacedDigit()
                        Text("\(a.plays)×").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if all.count > 5 {
                Button(showAllArtists ? "Show less" : "Show more") {
                    withAnimation { showAllArtists.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
        }
    }
}

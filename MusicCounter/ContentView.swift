import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var tracker: Tracker
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Retention.storageKey) private var retention = Retention.forever.rawValue
    @State private var showPlayer = false

    var body: some View {
        TabView {
            HomeView()
                .miniPlayer($showPlayer)
                .tabItem { Label("Today", systemImage: "waveform") }
            LibraryView()
                .miniPlayer($showPlayer)
                .tabItem { Label("Library", systemImage: "music.note.house.fill") }
            TracksView()
                .miniPlayer($showPlayer)
                .tabItem { Label("Tracks", systemImage: "music.note.list") }
            InsightsView()
                .miniPlayer($showPlayer)
                .tabItem { Label("Insights", systemImage: "chart.bar.fill") }
            HistoryView()
                .miniPlayer($showPlayer)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .tint(Theme.accent)
        .sheet(isPresented: $showPlayer) {
            NowPlayingView()
                .presentationDragIndicator(.hidden)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { tracker.reconcile() }
        }
        .onChange(of: retention) { _ in store.pruneHistory() }
    }
}

private struct MiniPlayerInset: ViewModifier {
    @EnvironmentObject var tracker: Tracker
    @Binding var showPlayer: Bool

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if let item = tracker.nowPlaying {
                MiniPlayerBar(item: item) { showPlayer = true }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: tracker.nowPlaying?.persistentID)
    }
}

extension View {
    /// Docks the mini player above the tab bar of this tab.
    func miniPlayer(_ showPlayer: Binding<Bool>) -> some View {
        modifier(MiniPlayerInset(showPlayer: showPlayer))
    }
}

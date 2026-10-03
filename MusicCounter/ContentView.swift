import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var tracker: Tracker
    @EnvironmentObject var sync: Sync
    @EnvironmentObject var achievements: Achievements
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
                .badge(achievements.unseen.count)
            HistoryView()
                .miniPlayer($showPlayer)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .tint(Theme.accent)
        .overlay(alignment: .top) {
            if let earned = achievements.justUnlocked.first {
                AchievementBanner(achievement: earned)
                    .id(earned.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { dismissBanner(earned.id) }
                    .task(id: earned.id) {
                        // Cancelled when the banner is tapped away first.
                        guard (try? await Task.sleep(nanoseconds: 3_500_000_000)) != nil else { return }
                        dismissBanner(earned.id)
                    }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: achievements.justUnlocked.first?.id)
        .sheet(isPresented: $showPlayer) {
            NowPlayingView()
                .presentationDragIndicator(.hidden)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { tracker.reconcile() }
            // Leaving the app: upload now rather than waiting out the debounce.
            if phase == .background {
                sync.push()
                BackgroundRefresh.schedule()
            }
        }
        .onChange(of: retention) { _ in
            store.pruneHistory()
            sync.retentionChanged()
        }
    }
}

extension ContentView {
    /// Shows the next earned badge, if several arrived at once.
    private func dismissBanner(_ id: String) {
        if achievements.justUnlocked.first?.id == id { achievements.justUnlocked.removeFirst() }
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

/// Room under a page's last row, enough to scroll it clear of the mini player.
private struct PageBottomMargin: ViewModifier {
    @EnvironmentObject var tracker: Tracker

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: tracker.nowPlaying == nil ? 24 : 100)
        }
    }
}

extension View {
    /// Leaves space at the bottom of a scrolling page for the mini player.
    func pageBottomMargin() -> some View {
        modifier(PageBottomMargin())
    }

    /// Docks the mini player above the tab bar of this tab.
    func miniPlayer(_ showPlayer: Binding<Bool>) -> some View {
        modifier(MiniPlayerInset(showPlayer: showPlayer))
    }
}

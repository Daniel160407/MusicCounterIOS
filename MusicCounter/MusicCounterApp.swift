import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct MusicCounterApp: App {
    @StateObject private var store: Store
    @StateObject private var tracker: Tracker
    @StateObject private var sync: Sync
    @StateObject private var achievements: Achievements
    @StateObject private var dailyGoal: DailyGoal

    init() {
        // Sync stays off (and the app works as before) until GoogleService-Info.plist is added.
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        let store = Store()
        let tracker = Tracker(store: store)
        let sync = Sync(store: store)
        let achievements = Achievements(store: store)
        let dailyGoal = DailyGoal(store: store)
        _store = StateObject(wrappedValue: store)
        _tracker = StateObject(wrappedValue: tracker)
        _sync = StateObject(wrappedValue: sync)
        _achievements = StateObject(wrappedValue: achievements)
        _dailyGoal = StateObject(wrappedValue: dailyGoal)
        BackgroundRefresh.configure(tracker: tracker, sync: sync, achievements: achievements, dailyGoal: dailyGoal)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(tracker)
                .environmentObject(sync)
                .environmentObject(achievements)
                .environmentObject(dailyGoal)
                .task {
                    tracker.start()
                    sync.start()
                    AchievementNotifier.shared.start()
                }
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
    }
}

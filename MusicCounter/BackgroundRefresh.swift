import Foundation
import BackgroundTasks

/// While the app is closed, iOS now and then wakes it for a few seconds: it credits
/// library plays made since, pulls the other devices' listening, and posts a
/// notification for any badge that earned and for reaching the daily goal. iOS decides when (and whether) that
/// happens — less often for apps you rarely open, never in Low Power Mode or with
/// Background App Refresh switched off.
@MainActor
enum BackgroundRefresh {
    /// Also listed under BGTaskSchedulerPermittedIdentifiers in Info.plist.
    nonisolated static let identifier = "com.daniel160407.MusicCounter.refresh"
    /// The soonest a refresh may run. iOS usually waits longer.
    private static let interval: TimeInterval = 60 * 60

    private static var tracker: Tracker?
    private static var sync: Sync?
    private static var achievements: Achievements?
    private static var dailyGoal: DailyGoal?

    static func configure(tracker: Tracker, sync: Sync, achievements: Achievements, dailyGoal: DailyGoal) {
        self.tracker = tracker
        self.sync = sync
        self.achievements = achievements
        self.dailyGoal = dailyGoal
    }

    /// Asks for the next refresh; called on leaving the app and at the start of each run.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        // Fails in the Simulator and when Background App Refresh is off; nothing to do then.
        try? BGTaskScheduler.shared.submit(request)
    }

    static func run() async {
        schedule()
        tracker?.reconcile()
        await sync?.refresh()
        sync?.push()
        if let fresh = achievements?.evaluate(announce: false), !fresh.isEmpty {
            await AchievementNotifier.shared.post(fresh)
        }
        dailyGoal?.check(announce: false)
    }
}

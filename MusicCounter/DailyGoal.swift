import SwiftUI
import Combine
import UserNotifications

extension Store {
    /// The goal grows with you: one hour more than you listened yesterday, on every
    /// device — the same goal the browser extension sets.
    var dailyGoal: Double { (lastDays(2).first?.seconds ?? 0) + 3600 }
}

/// Announces reaching the daily goal, once a day: a notification with the
/// achievement chime, and an in-app banner while the app is open — like the
/// extension's notification.
@MainActor
final class DailyGoal: ObservableObject {
    /// Set when the goal is reached with the app open; shown as a banner, then cleared.
    @Published var justReached: Double?

    private static let announcedKey = "dailyGoalAnnounced"
    private let store: Store
    private var cancellable: AnyCancellable?

    init(store: Store) {
        self.store = store
        cancellable = store.objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.check() }
    }

    func check(announce: Bool = true) {
        let day = Self.dayFormatter.string(from: Date())
        guard UserDefaults.standard.string(forKey: Self.announcedKey) != day else { return }
        let today = store.todaySeconds
        guard today >= store.dailyGoal else { return }
        UserDefaults.standard.set(day, forKey: Self.announcedKey)
        if announce, UIApplication.shared.applicationState == .active {
            justReached = today
            AchievementNotifier.shared.playChime()
        }
        Task { await Self.post(today: today, day: day) }
    }

    private static func post(today: Double, day: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Daily goal reached"
        content.body = "You've listened \(formatDuration(today)) today — an hour more than yesterday."
        content.sound = UNNotificationSound(named: UNNotificationSoundName(AchievementNotifier.soundFile))
        content.threadIdentifier = "daily-goal"
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: "daily-goal-\(day)", content: content, trigger: nil))
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

struct GoalBanner: View {
    let seconds: Double

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.green)
                Image(systemName: "target").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily goal reached").font(.headline)
                Text("You've listened \(formatDuration(seconds)) today — an hour more than yesterday.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
}

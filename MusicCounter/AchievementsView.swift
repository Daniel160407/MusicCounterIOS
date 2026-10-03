import SwiftUI

/// Summary on the Insights page: how many badges are earned, the latest few, and a link to all of them.
struct AchievementsCard: View {
    @EnvironmentObject var achievements: Achievements

    var body: some View {
        let statuses = achievements.statuses
        let earned = statuses.filter { $0.unlockedAt != nil }.sorted { $0.unlockedAt! > $1.unlockedAt! }
        let next = statuses.filter { $0.unlockedAt == nil && $0.achievement.unit != .flag }.max { $0.progress < $1.progress }

        NavigationLink {
            AchievementsView()
        } label: {
            Card {
                HStack(alignment: .firstTextBaseline) {
                    Text("Achievements").font(.headline)
                    if !achievements.unseen.isEmpty {
                        Text("\(achievements.unseen.count) new")
                            .font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                    }
                    Spacer()
                    Text("\(earned.count)/\(statuses.count)").font(.subheadline.weight(.semibold)).monospacedDigit()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }

                ProgressView(value: Double(earned.count), total: Double(max(statuses.count, 1)))
                    .tint(Theme.accent)

                if !earned.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(earned.prefix(5)) { BadgeIcon(status: $0, size: 40) }
                        Spacer(minLength: 0)
                    }
                }

                if let next {
                    Text("Closest: \(next.achievement.title) — \(next.progressText)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct AchievementsView: View {
    @EnvironmentObject var achievements: Achievements
    /// Captured on opening, so badges keep their "New" tag while you look at them.
    @State private var fresh: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                ForEach(Achievement.groups, id: \.self) { group in
                    let items = achievements.statuses.filter { $0.achievement.group == group }
                    Card(title: "\(group) · \(items.filter { $0.unlockedAt != nil }.count)/\(items.count)") {
                        ForEach(items) { AchievementRow(status: $0, fresh: fresh.contains($0.id)) }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .pageBottomMargin()
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fresh = achievements.unseen
            achievements.markSeen()
        }
    }

    private var header: some View {
        let total = achievements.statuses.count
        let earned = achievements.earnedCount
        return Card {
            HStack(spacing: 16) {
                ZStack {
                    ProgressRing(progress: Double(earned) / Double(max(total, 1)), lineWidth: 10)
                    VStack(spacing: 0) {
                        Text("\(earned)").font(.title.weight(.bold)).monospacedDigit()
                        Text("of \(total)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text(earned == total ? "All earned" : "Keep listening").font(.title3.weight(.semibold))
                    Text("Badges count listening from every synced device, and stay earned after a reset.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AchievementRow: View {
    let status: AchievementStatus
    let fresh: Bool

    var body: some View {
        let a = status.achievement
        HStack(spacing: 12) {
            BadgeIcon(status: status, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(a.title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(status.unlockedAt == nil ? .secondary : .primary)
                    if fresh {
                        Text("NEW").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.accent, in: Capsule())
                    }
                }
                Text(a.text).font(.caption).foregroundStyle(.secondary)
                if let date = status.unlockedAt {
                    Text("Earned \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2.weight(.medium)).foregroundStyle(Theme.accent)
                } else if a.unit != .flag {
                    ProgressView(value: status.progress).tint(Theme.accent)
                    Text(status.progressText).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct BadgeIcon: View {
    let status: AchievementStatus
    var size: CGFloat = 44

    var body: some View {
        let earned = status.unlockedAt != nil
        ZStack {
            Circle().fill(earned ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
            Image(systemName: status.achievement.symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(earned ? Color.white : Color.secondary.opacity(0.6))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(status.achievement.title)
    }
}

/// Slides in from the top when a badge is earned while the app is open.
struct AchievementBanner: View {
    let achievement: Achievement

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.gradient)
                Image(systemName: achievement.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("Achievement unlocked").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(achievement.title).font(.headline)
                Text(achievement.text).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
}

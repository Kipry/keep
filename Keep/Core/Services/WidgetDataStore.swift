import Foundation
import SwiftData
import WidgetKit

// Writes the widget's snapshot to the shared App Group. The widget cannot read
// SwiftData, so everything it draws — including the streak and this week's
// recording days — is precomputed here and stored as a small JSON blob.
enum WidgetDataStore {
    static let groupID = "group.com.kipry.keep.app"
    /// Versioned key: the payload gained fields, and a stale v1 blob would fail
    /// to decode. A new key simply reads as "no snapshot yet" until the app
    /// writes once, instead of surfacing a decode error as an empty widget.
    static let key = "projectSnapshotV2"

    struct Snapshot: Codable {
        let id: String
        let name: String
        let clipCount: Int
        let totalDuration: Double
        let thumbnailData: Data?
        /// Days since the project was created — drives "FOR n DAYS".
        let runningDays: Int
        /// Consecutive recording days ending today or yesterday; 0 once broken.
        let streak: Int
        /// Seven flags, oldest first, last entry is today.
        let week: [Bool]
        /// False while the project has a single clip — the stacked back card
        /// only makes sense once there's actually more than one.
        let hasMultipleClips: Bool
        /// Caption under the polaroid: when this project was last added to.
        let lastClipDate: Date?
    }

    /// Recomputes and stores the snapshot. Call after anything that changes
    /// clips or projects; it reads what it needs from the context itself so
    /// callers don't have to assemble cross-project data.
    static func refresh(context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let allClips = ((try? context.fetch(FetchDescriptor<Clip>())) ?? [])
            .filter { !$0.isDeleted && !($0.project?.isDeleted ?? false) }
        let recordedDays = Set(allClips.map { calendar.startOfDay(for: $0.createdAt) })

        let projects = ((try? context.fetch(FetchDescriptor<Project>())) ?? [])
            .filter { !$0.isDeleted && !$0.isArchived }
        guard let project = projects.max(by: { $0.updatedAt < $1.updatedAt }) else {
            clear()
            return
        }

        let clips = project.activeClips
        let snapshot = Snapshot(
            id: project.id.uuidString,
            name: project.name,
            clipCount: clips.count,
            totalDuration: clips.reduce(0) { $0 + $1.effectiveDuration },
            thumbnailData: project.coverThumbnailData ?? clips.first?.thumbnailData,
            runningDays: max(0, calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: project.createdAt), to: today).day ?? 0),
            streak: streak(in: recordedDays, today: today, calendar: calendar),
            week: week(in: recordedDays, today: today, calendar: calendar),
            hasMultipleClips: clips.count > 1,
            lastClipDate: clips.map(\.createdAt).max()
        )

        guard let defaults = UserDefaults(suiteName: groupID),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> Snapshot? {
        guard let defaults = UserDefaults(suiteName: groupID),
              let data = defaults.data(forKey: key),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        return snap
    }

    private static func clear() {
        UserDefaults(suiteName: groupID)?.removeObject(forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Derived values

    /// Counts back from today. Recording today isn't required — a streak stays
    /// alive until the day after the last recording passes, so opening the app
    /// in the morning doesn't show a streak that "broke" overnight.
    private static func streak(in days: Set<Date>, today: Date, calendar: Calendar) -> Int {
        var cursor = today
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private static func week(in days: Set<Date>, today: Date, calendar: Calendar) -> [Bool] {
        (0..<7).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return false }
            return days.contains(day)
        }
    }
}

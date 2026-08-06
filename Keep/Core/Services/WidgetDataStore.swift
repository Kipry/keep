import Foundation
import SwiftData
import WidgetKit

// MARK: - WidgetInstallation

/// Whether the user has actually put a keep. widget on a screen.
///
/// The lock-screen widget is the whole point of the app, and the onboarding
/// step that explains it is the one people tap past. A reminder is only
/// tolerable if it can tell — it must never appear for someone who already has
/// the widget, and must disappear the moment they add one. Anything that can't
/// tell is a nag.
///
/// Counts *any* family, not just `.accessoryCircular`: someone running the
/// medium home-screen widget already has a one-tap record button and does not
/// need to be told about widgets.
@Observable
final class WidgetInstallation {
    static let shared = WidgetInstallation()

    /// Optimistic until proven otherwise, so the card can't flash on screen
    /// during the first query — and a query that fails is treated as "has one",
    /// because guessing wrong in that direction only costs a missed hint.
    private(set) var hasWidget = true

    private init() {}

    func refresh() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            let installed: Bool
            switch result {
            case .success(let infos): installed = !infos.isEmpty
            case .failure:            installed = true
            }
            Task { @MainActor in WidgetInstallation.shared.hasWidget = installed }
        }
    }
}

// Writes the widget's snapshot to the shared App Group. The widget cannot read
// SwiftData, so everything it draws — including the streak and this week's
// recording days — is precomputed here and stored as a small JSON blob.
enum WidgetDataStore {
    static let groupID = "group.com.kipry.keep.app"
    /// Versioned key: the payload gained fields, and a stale v1 blob would fail
    /// to decode. A new key simply reads as "no snapshot yet" until the app
    /// writes once, instead of surfacing a decode error as an empty widget.
    static let key = "projectSnapshotV3"

    /// Everything the widget draws.
    ///
    /// Nothing here is relative to "today" any more. v2 stored a ready-made
    /// `streak: Int` and a seven-flag `week: [Bool]`, both meaning "as of the
    /// moment the app last wrote this" — so a phone left alone overnight showed
    /// yesterday's answer: the flame still lit, the last box in the strip still
    /// filled, as though the day already had a recording. The widget now gets
    /// absolute dates and works out both itself, for whatever day it happens to
    /// be rendering.
    struct Snapshot: Codable {
        let id: String
        let name: String
        let clipCount: Int
        let totalDuration: Double
        let thumbnailData: Data?
        /// Start-of-day stamps of every day with a recording in the last two
        /// weeks — enough for the seven-day strip on any day the widget might
        /// still be showing this snapshot.
        let recentDays: [Date]
        /// Most recent day with a recording, never in the future.
        let lastRecordingDay: Date?
        /// Consecutive recording days ending at `lastRecordingDay`. Whether
        /// that run is still *alive* is the widget's call, since it depends on
        /// what day it is when the widget draws.
        let streakLength: Int
        /// False while the project has a single clip — the stacked back card
        /// only makes sense once there's actually more than one.
        let hasMultipleClips: Bool
        /// When the clip shown on the polaroid was recorded — its caption.
        let featuredClipDate: Date?
    }

    /// Recomputes and stores the snapshot. Call after anything that changes
    /// clips or projects; it reads what it needs from the context itself so
    /// callers don't have to assemble cross-project data.
    static func refresh(context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let allClips = ((try? context.fetch(FetchDescriptor<Clip>())) ?? [])
            .filter { !$0.isTrashed && !($0.project?.isTrashed ?? false) }
        let recordedDays = Set(allClips.map { calendar.startOfDay(for: $0.createdAt) })
        // Clamped to today: a photo imported with a broken EXIF date can sit in
        // the future, and a future last day would keep the streak "alive"
        // forever.
        let lastDay = recordedDays.filter { $0 <= today }.max()

        let projects = ((try? context.fetch(FetchDescriptor<Project>())) ?? [])
            .filter { !$0.isTrashed && !$0.isArchived }
        guard let project = projects.max(by: { $0.updatedAt < $1.updatedAt }) else {
            clear()
            return
        }

        let clips = project.activeClips
        // Picture and caption come from ONE clip, so the polaroid can't end up
        // dated with some other clip's timestamp. The newest rather than the
        // project cover: the cover is set once from the first clip and then
        // never moves, so the widget would show the oldest moment forever
        // instead of the one just recorded. (It also isn't derivable — Project
        // stores the cover's bytes, not which clip they came from.)
        let featured = clips.filter { $0.thumbnailData != nil }
                            .max(by: { $0.createdAt < $1.createdAt })
        let snapshot = Snapshot(
            id: project.id.uuidString,
            name: project.name,
            clipCount: clips.count,
            totalDuration: clips.reduce(0) { $0 + $1.effectiveDuration },
            thumbnailData: featured?.thumbnailData,
            recentDays: recentDays(in: recordedDays, today: today, calendar: calendar),
            lastRecordingDay: lastDay,
            streakLength: streakLength(endingAt: lastDay, in: recordedDays, calendar: calendar),
            hasMultipleClips: clips.count > 1,
            featuredClipDate: featured?.createdAt
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

    /// Length of the unbroken run of recording days ending at `last`. Says
    /// nothing about whether the run is still alive — that depends on the day
    /// the widget renders, so the widget decides it.
    private static func streakLength(endingAt last: Date?, in days: Set<Date>,
                                     calendar: Calendar) -> Int {
        guard var cursor = last else { return 0 }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// The recording days the widget could still need. Fourteen days back
    /// covers the seven-day strip even if the widget goes on rendering this
    /// snapshot for a week without the app being opened.
    private static func recentDays(in days: Set<Date>, today: Date, calendar: Calendar) -> [Date] {
        guard let cutoff = calendar.date(byAdding: .day, value: -14, to: today) else {
            return days.sorted()
        }
        return days.filter { $0 >= cutoff }.sorted()
    }
}

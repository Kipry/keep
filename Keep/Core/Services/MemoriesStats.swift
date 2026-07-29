import Foundation

/// Everything the Memories tab derives from the clip list, computed in one
/// pass.
///
/// This used to live as a dozen computed properties on the view. SwiftUI does
/// not memoise those, and several of them called each other — `bestStreak`
/// re-derived `uniqueRecordingDays` *and* `currentStreak`, the body read each
/// lookback window two or three times, and the weekday row ran seven separate
/// linear scans. That worked out to roughly twenty full traversals of every
/// clip in the database per body evaluation, each doing a `Calendar` call per
/// clip, on a view `ContentView` keeps permanently mounted.
///
/// Calendar arithmetic is handled defensively throughout. The view used to
/// force-unwrap `Calendar.date(byAdding:)` in eleven places; it returns an
/// optional for a reason, and `Calendar.current` follows the device region.
struct MemoriesStats {
    var recordingDays = 0
    var totalDurationLabel = "0s"
    /// Days with at least one clip, newest first.
    var uniqueDays: [Date] = []
    /// Same days as a set — the weekday row asks about seven specific days.
    var daySet: Set<Date> = []
    var clipsByDay: [Date: [Clip]] = [:]
    var currentStreak = 0
    var bestStreak = 0
    /// A fortnight centred on this date last year. The week and month windows
    /// that used to live here went with the lookback strips they fed — the year
    /// spiral covers that ground now, and better.
    var lastYear: [(Date, [Clip])] = []

    static let empty = MemoriesStats()

    static func build(clips: [Clip], calendar: Calendar) -> MemoriesStats {
        var stats = MemoriesStats()
        guard !clips.isEmpty else { return stats }

        let today = calendar.startOfDay(for: Date())

        // One pass for the day bucketing everything else is derived from.
        var byDay: [Date: [Clip]] = [:]
        var total = 0.0
        for clip in clips {
            byDay[calendar.startOfDay(for: clip.createdAt), default: []].append(clip)
            total += clip.effectiveDuration
        }
        for key in byDay.keys {
            byDay[key]?.sort { $0.createdAt < $1.createdAt }
        }

        stats.clipsByDay = byDay
        stats.daySet = Set(byDay.keys)
        stats.uniqueDays = byDay.keys.sorted(by: >)
        stats.recordingDays = byDay.count
        stats.totalDurationLabel = durationLabel(total)

        stats.currentStreak = currentStreak(days: stats.daySet, today: today, calendar: calendar)
        stats.bestStreak = max(bestStreak(days: stats.uniqueDays, calendar: calendar),
                               stats.currentStreak)

        let sortedDays = stats.uniqueDays.sorted()
        func window(_ start: Date?, _ end: Date?) -> [(Date, [Clip])] {
            guard let start, let end else { return [] }
            return sortedDays
                .filter { $0 >= start && $0 < end }
                .map { ($0, byDay[$0] ?? []) }
        }

        let anchor = calendar.date(byAdding: .year, value: -1, to: today)
        stats.lastYear = window(
            anchor.flatMap { calendar.date(byAdding: .day, value: -7, to: $0) },
            anchor.flatMap { calendar.date(byAdding: .day, value: 8, to: $0) }
        )

        return stats
    }

    // MARK: Derived

    /// Counts back from today, or from yesterday if nothing is recorded yet
    /// today — a morning without a recording shouldn't read as a broken streak.
    private static func currentStreak(days: Set<Date>, today: Date, calendar: Calendar) -> Int {
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

    /// Longest run of consecutive days anywhere in the history.
    private static func bestStreak(days: [Date], calendar: Calendar) -> Int {
        guard !days.isEmpty else { return 0 }
        var best = 1, run = 1
        for i in 1..<days.count {
            // `days` is newest first, so the previous entry should be one day later.
            guard let expected = calendar.date(byAdding: .day, value: -1, to: days[i - 1]) else {
                run = 1; continue
            }
            if days[i] == expected {
                run += 1
                best = max(best, run)
            } else {
                run = 1
            }
        }
        return best
    }

    private static func durationLabel(_ t: Double) -> String {
        if t < 60   { return String(format: "%.0fs", t) }
        if t < 3600 { return String(format: "%dm", Int(t) / 60) }
        return String(format: "%dh %dm", Int(t) / 3600, (Int(t) % 3600) / 60)
    }
}

import WidgetKit
import SwiftUI

// MARK: - Shared data model
//
// Mirrors WidgetDataStore.Snapshot in the app target. The widget can't read
// SwiftData, so everything it draws is precomputed there and read back here.

private struct ProjectSnapshot: Codable {
    let id: String
    let name: String
    let clipCount: Int
    let totalDuration: Double
    let thumbnailData: Data?
    let streak: Int
    let week: [Bool]
    let hasMultipleClips: Bool
    let lastClipDate: Date?

    /// The streak is alive as long as it has any length — the app only counts
    /// days up to yesterday, so a morning without a recording doesn't kill it.
    var streakAlive: Bool { streak > 0 }
}

private func loadSnapshot() -> ProjectSnapshot? {
    guard let defaults = UserDefaults(suiteName: "group.com.kipry.keep.app"),
          let data = defaults.data(forKey: "projectSnapshotV2"),
          let snap = try? JSONDecoder().decode(ProjectSnapshot.self, from: data) else { return nil }
    return snap
}

// MARK: - Timeline

struct KeepEntry: TimelineEntry {
    let date: Date
    fileprivate let snapshot: ProjectSnapshot?
}

struct KeepProvider: TimelineProvider {
    func placeholder(in context: Context) -> KeepEntry {
        KeepEntry(date: .now, snapshot: ProjectSnapshot(
            id: "preview", name: "Summer 2026",
            clipCount: 46, totalDuration: 68, thumbnailData: nil,
            streak: 12,
            week: [true, true, false, true, true, true, false],
            hasMultipleClips: true, lastClipDate: .now))
    }
    func getSnapshot(in context: Context, completion: @escaping (KeepEntry) -> Void) {
        completion(KeepEntry(date: .now, snapshot: loadSnapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<KeepEntry>) -> Void) {
        let entry = KeepEntry(date: .now, snapshot: loadSnapshot())
        // Refresh at the next midnight so "today" in the week strip moves on
        // even if the app isn't opened.
        let midnight = Calendar.current.nextDate(
            after: .now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime)
        completion(Timeline(entries: [entry], policy: midnight.map { .after($0) } ?? .never))
    }
}

// MARK: - Palette (hardcoded — no dependency on the main app module)

private let amber   = Color(red: 0.941, green: 0.529, blue: 0.227)   // #F0873A
private let ink     = Color(red: 0.102, green: 0.102, blue: 0.102)   // #1A1A1A
private let paper   = Color(red: 0.961, green: 0.902, blue: 0.784)   // #F5E6C8
private let cream   = Color(red: 0.929, green: 0.851, blue: 0.639)   // #EDD9A3
private let dimGap  = Color(red: 0.161, green: 0.161, blue: 0.161)   // #292929

private func recordURL(for id: String) -> URL {
    URL(string: "keep://record/\(id)")!
}

private func openURL(for id: String) -> URL {
    URL(string: "keep://open/\(id)")!
}

private let diaryURL = URL(string: "keep://diary")!

private func durationLabel(_ t: Double) -> String {
    guard t > 0 else { return "—" }
    return t < 60 ? String(format: "%.0fs", t)
                  : String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
}

// MARK: - Home-screen widget view

struct HomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KeepEntry

    var body: some View {
        switch family {
        case .systemMedium: medium
        default:            small
        }
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snap = entry.snapshot {
                Text(snap.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(snap.clipCount) clip\(snap.clipCount == 1 ? "" : "s") · \(durationLabel(snap.totalDuration))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 5)
            } else {
                Text("No project")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer()

            // Only the REC button triggers record deep-link; tapping elsewhere opens the project.
            if let snap = entry.snapshot {
                Link(destination: recordURL(for: snap.id)) {
                    recPill
                }
            } else {
                recPill
            }
        }
        .padding(16)
        .widgetURL(entry.snapshot.map { openURL(for: $0.id) })
    }

    private var recPill: some View {
        Text("REC")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(amber, in: Capsule())
    }

    // MARK: Medium — "the running project"
    //
    // A portrait polaroid of the active project (clips are shot 9:16, so the
    // frame matches the footage without cropping), the project's numbers, this
    // week's recording days, and the shutter. Answers "what am I working on?"
    // rather than "did I record today?" — and needs a single image to do it.

    private var medium: some View {
        Group {
            if let snap = entry.snapshot {
                HStack(spacing: 16) {
                    Link(destination: openURL(for: snap.id)) {
                        polaroidStack(snap)
                    }
                    infoColumn(snap)
                    Link(destination: recordURL(for: snap.id)) {
                        shutter
                    }
                }
            } else {
                emptyBody
            }
        }
        // Asymmetric on purpose: the polaroid sits closer to the edge so it
        // reads as a physical card lying on the widget, and the extra gap goes
        // between the card and the text instead.
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 13)
    }

    // MARK: Polaroid

    /// Front card plus a second one peeking out behind it — the stack is what
    /// turns a single still into "a reel". Dropped for a one-clip project,
    /// where a stack would be a lie.
    private func polaroidStack(_ snap: ProjectSnapshot) -> some View {
        ZStack(alignment: .topLeading) {
            if snap.hasMultipleClips {
                polaroidCard(image: nil, caption: nil, fill: cream, showsPlaceholder: false)
                    .rotationEffect(.degrees(4))
                    .offset(x: 5, y: 4)
            }
            polaroidCard(
                image: snap.thumbnailData.flatMap(UIImage.init(data:)),
                caption: snap.lastClipDate.map(Self.captionFormatter.string(from:)),
                fill: paper,
                showsPlaceholder: true
            )
            .rotationEffect(.degrees(-1.5))
        }
        .frame(maxHeight: .infinity)
    }

    private func polaroidCard(image: UIImage?, caption: String?,
                              fill: Color, showsPlaceholder: Bool) -> some View {
        VStack(spacing: 0) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if showsPlaceholder {
                    Rectangle()
                        .fill(ink.opacity(0.10))
                        .overlay {
                            Image(systemName: "film")
                                .font(.system(size: 15))
                                .foregroundStyle(ink.opacity(0.32))
                        }
                } else {
                    Rectangle().fill(fill)
                }
            }
            .frame(width: 54)
            .frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            Text(caption ?? " ")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(ink.opacity(0.55))
                .lineLimit(1)
                .padding(.top, 6)
                .padding(.bottom, 7)
        }
        .padding(.horizontal, 5)
        .padding(.top, 5)
        .background(fill, in: RoundedRectangle(cornerRadius: 9))
    }

    private static let captionFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    // MARK: Info column

    private func infoColumn(_ snap: ProjectSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(snap.name)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(snap.clipCount) CLIPS · \(durationLabel(snap.totalDuration))")
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .padding(.top, 5)

            Spacer(minLength: 6)

            Link(destination: diaryURL) {
                VStack(alignment: .leading, spacing: 0) {
                    streakRow(snap)
                    weekStrip(snap).padding(.top, 7)
                    Text("THIS WEEK")
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.32))
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Amber flame while the streak lives, grey "ENDED" once it breaks — the
    /// state differs in fill and wording, not only hue, so it survives the
    /// tinted home screen.
    private func streakRow(_ snap: ProjectSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "flame.fill")
                .font(.system(size: 19))
            if snap.streakAlive {
                Text("\(snap.streak)")
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                Text("DAYS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1)
            } else {
                Text("ENDED")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(1)
            }
        }
        .foregroundStyle(snap.streakAlive ? amber : Color.white.opacity(0.32))
        .widgetAccentable(snap.streakAlive)
    }

    private func weekStrip(_ snap: ProjectSnapshot) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(snap.week.enumerated()), id: \.offset) { index, recorded in
                let isToday = index == snap.week.count - 1
                RoundedRectangle(cornerRadius: 3)
                    .fill(recorded ? amber : (isToday ? .clear : dimGap))
                    .overlay {
                        if !recorded {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(isToday ? amber : .white.opacity(0.07),
                                              lineWidth: isToday ? 2 : 1)
                        }
                    }
                    .frame(height: 16)
                    .widgetAccentable(recorded || isToday)
            }
        }
    }

    // MARK: Shutter

    /// Ring plus dot — the same shutter language as the lock-screen widget,
    /// without the gradient and shadow that made it read as a glossy button.
    private var shutter: some View {
        ZStack {
            Circle()
                .strokeBorder(amber.opacity(0.5), lineWidth: 2)
            Circle()
                .fill(amber)
                .frame(width: 22, height: 22)
        }
        .frame(width: 46, height: 46)
        .widgetAccentable()
    }

    // MARK: Empty state
    //
    // No project yet: the frame stays, empty, so the widget reads as waiting
    // rather than broken. No Link — tapping anywhere opens the app.

    private var emptyBody: some View {
        HStack(spacing: 16) {
            polaroidCard(image: nil, caption: nil, fill: paper, showsPlaceholder: true)
            VStack(alignment: .leading, spacing: 5) {
                Text("New project")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Three seconds, and today is in.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            shutter
        }
    }
}

// MARK: - Lock-screen widget view (accessoryCircular)

struct LockWidgetView: View {
    let entry: KeepEntry

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .strokeBorder(amber.opacity(0.55), lineWidth: 2)

            VStack(spacing: 2) {
                Circle()
                    .fill(amber)
                    .frame(width: 10, height: 10)
                Text("REC")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(amber)
            }
            .offset(y: 3)
        }
        .widgetURL(entry.snapshot.map { recordURL(for: $0.id) })
    }
}

// MARK: - Widget configurations

// Home-screen widget (small + medium)
struct KeepHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeepHomeWidget", provider: KeepProvider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(
                    Color(red: 0.121, green: 0.121, blue: 0.121),
                    for: .widget
                )
        }
        .configurationDisplayName("keep.")
        .description("Your running project — and this week at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// Lock-screen widget (circular)
struct KeepLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeepLockWidget", provider: KeepProvider()) { entry in
            LockWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("keep. · REC")
        .description("Quick-record into your latest project from the Lock Screen.")
        .supportedFamilies([.accessoryCircular])
    }
}

// Bundle — registers both widgets
@main
struct KeepWidgetBundle: WidgetBundle {
    var body: some Widget {
        KeepHomeWidget()
        KeepLockWidget()
    }
}

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

    // At this size a thumbnail plus text leaves neither enough room, so the
    // small widget answers the question that actually comes up daily — "am I
    // still going?" — while the medium keeps the project and its footage. It
    // reuses the medium's streak block and week strip rather than shrinking its
    // layout, so the two are complementary rather than one being a crop of the
    // other. Being image-free it also stays sharp in every rendering mode.
    // A systemSmall widget has a single tap target, so the whole thing records.

    private var small: some View {
        Group {
            if let snap = entry.snapshot {
                smallBody(snap)
            } else {
                smallEmpty
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(entry.snapshot.map { recordURL(for: $0.id) })
    }

    private func smallBody(_ snap: ProjectSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Text(snap.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                Spacer(minLength: 4)
                shutterMark
            }

            Spacer(minLength: 8)

            // A bare "0" reads as failure, so a broken streak gets the sentence
            // that says what to do instead of a number to feel bad about.
            if snap.streakAlive {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 20))
                    Text("\(snap.streak)")
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(amber)
                .widgetAccentable()

                Text(snap.streak == 1 ? "DAY IN A ROW" : "DAYS IN A ROW")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 3)
            } else {
                Text("Three seconds,\nand today is in.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            weekStrip(snap)
            Text("THIS WEEK")
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.32))
                .padding(.top, 6)
        }
    }

    private var smallEmpty: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                shutterMark
            }
            Spacer()
            Text("New project")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text("Three seconds,\nand today is in.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
            Spacer()
        }
    }

    /// The medium widget's ring-and-dot shutter at small-widget scale.
    private var shutterMark: some View {
        ZStack {
            Circle().strokeBorder(amber.opacity(0.5), lineWidth: 2)
            Circle().fill(amber).frame(width: 14, height: 14)
        }
        .frame(width: 30, height: 30)
        .widgetAccentable()
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
        .padding(.leading, 8)
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
                // Held back in opacity and pushed further out than before:
                // opacity is the one property that survives every rendering
                // mode, so it — not the cream/paper colour difference — is
                // what makes this read as a card lying underneath.
                polaroidCard(image: nil, fill: cream.opacity(0.5),
                             showsPlaceholder: false, photoWidth: 54) {
                    dateCaption(nil)
                }
                .rotationEffect(.degrees(5))
                .offset(x: 7, y: 5)
            }
            polaroidCard(
                image: snap.thumbnailData.flatMap(UIImage.init(data:)),
                fill: paper,
                showsPlaceholder: true,
                photoWidth: 54
            ) {
                dateCaption(snap.lastClipDate.map(Self.captionFormatter.string(from:)))
            }
            .rotationEffect(.degrees(-1.5))
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func polaroidPhoto(image: UIImage?, fill: Color, showsPlaceholder: Bool) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                // Without this the tinted and clear home screen styles flatten
                // the photo into the tint colour, so the clip vanished entirely
                // — the one element that must stay recognisable.
                .widgetAccentedRenderingMode(.fullColor)
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

    /// `photoWidth` nil means the photo fills the available width (small
    /// widget); a value pins it (the medium's portrait frame).
    private func polaroidCard<Caption: View>(
        image: UIImage?,
        fill: Color,
        showsPlaceholder: Bool,
        photoWidth: CGFloat?,
        @ViewBuilder caption: () -> Caption
    ) -> some View {
        VStack(spacing: 0) {
            Group {
                if let photoWidth {
                    polaroidPhoto(image: image, fill: fill, showsPlaceholder: showsPlaceholder)
                        .frame(width: photoWidth)
                        .frame(maxHeight: .infinity)
                } else {
                    polaroidPhoto(image: image, fill: fill, showsPlaceholder: showsPlaceholder)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))

            caption()
                .padding(.top, 6)
                .padding(.bottom, 7)
        }
        .padding(.horizontal, 5)
        .padding(.top, 5)
        .background(fill, in: RoundedRectangle(cornerRadius: 9))
        // Outlines the paper so one card's edge stays readable against the
        // next — without it the stack merges into a single blob wherever the
        // two cards are rendered in the same colour.
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(ink.opacity(0.22), lineWidth: 1)
        )
    }

    private func dateCaption(_ text: String?) -> some View {
        Text(text ?? " ")
            .font(.system(size: 7, weight: .medium, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(ink.opacity(0.55))
            .lineLimit(1)
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

    /// Recorded days are solid, missed days are hollow. The distinction has to
    /// be fill-vs-outline rather than two colours: the tinted and clear home
    /// screen styles discard hue but keep opacity, so the old opaque grey box
    /// for a missed day rendered as a solid tinted box — identical to a day
    /// that was actually recorded.
    private func weekStrip(_ snap: ProjectSnapshot) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(snap.week.enumerated()), id: \.offset) { index, recorded in
                let isToday = index == snap.week.count - 1
                RoundedRectangle(cornerRadius: 3)
                    .fill(recorded ? amber : Color.clear)
                    .overlay {
                        if !recorded {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(isToday ? amber : Color.white.opacity(0.28),
                                              lineWidth: isToday ? 2 : 1.5)
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
            polaroidCard(image: nil, fill: paper,
                         showsPlaceholder: true, photoWidth: 54) {
                dateCaption(nil)
            }
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

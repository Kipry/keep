import WidgetKit
import SwiftUI

// MARK: - Shared data model

private struct ProjectSnapshot: Codable {
    let id: String
    let name: String
    let clipCount: Int
    let totalDuration: Double
    let thumbnailData: Data?
}

private func loadSnapshot() -> ProjectSnapshot? {
    guard let defaults = UserDefaults(suiteName: "group.com.lifeclip.app"),
          let data = defaults.data(forKey: "lastProject"),
          let snap = try? JSONDecoder().decode(ProjectSnapshot.self, from: data) else { return nil }
    return snap
}

// MARK: - Timeline

struct LifeClipEntry: TimelineEntry {
    let date: Date
    let snapshot: ProjectSnapshot?
}

struct LifeClipProvider: TimelineProvider {
    func placeholder(in context: Context) -> LifeClipEntry {
        LifeClipEntry(date: .now, snapshot: ProjectSnapshot(
            id: "preview", name: "Summer 2026",
            clipCount: 12, totalDuration: 36, thumbnailData: nil))
    }
    func getSnapshot(in context: Context, completion: @escaping (LifeClipEntry) -> Void) {
        completion(LifeClipEntry(date: .now, snapshot: loadSnapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LifeClipEntry>) -> Void) {
        let entry = LifeClipEntry(date: .now, snapshot: loadSnapshot())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Colours (hardcoded — no dependency on main app module)

private let amber = Color(red: 0.941, green: 0.529, blue: 0.227)
private let ink   = Color(red: 0.102, green: 0.102, blue: 0.102)

private func recordURL(for id: String) -> URL {
    URL(string: "lifeclip://record/\(id)")!
}

private func openURL(for id: String) -> URL {
    URL(string: "lifeclip://open/\(id)")!
}

private func durationLabel(_ t: Double) -> String {
    guard t > 0 else { return "—" }
    return t < 60 ? String(format: "%.0fs", t)
                  : String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
}

// MARK: - Home-screen widget view

struct HomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LifeClipEntry

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
                    recButton(label: "⏺ REC", compact: false)
                }
            } else {
                recButton(label: "⏺ REC", compact: false)
            }
        }
        .padding(16)
        .widgetURL(entry.snapshot.map { openURL(for: $0.id) })
    }

    // MARK: Medium

    private var medium: some View {
        HStack(spacing: 0) {
            // Thumbnail pane — left half
            Group {
                if let data = entry.snapshot?.thumbnailData,
                   let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.05)
                        .overlay(
                            Image(systemName: "film")
                                .font(.system(size: 24))
                                .foregroundStyle(.white.opacity(0.12))
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Info pane — right half
            VStack(alignment: .leading, spacing: 0) {
                Text("LIFECLIP")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.3))

                Spacer()

                if let snap = entry.snapshot {
                    Text(snap.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text("\(snap.clipCount) clips · \(durationLabel(snap.totalDuration))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 3)
                } else {
                    Text("Open LifeClip\nto get started")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.3))
                }

                Spacer()
                if let snap = entry.snapshot {
                    Link(destination: recordURL(for: snap.id)) {
                        recButton(label: "⏺ Record Clip", compact: false)
                    }
                } else {
                    recButton(label: "⏺ Record Clip", compact: false)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .widgetURL(entry.snapshot.map { openURL(for: $0.id) })
    }

    // MARK: Shared button

    private func recButton(label: String, compact: Bool) -> some View {
        Text(label)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(amber, in: Capsule())
    }
}

// MARK: - Lock-screen widget view (accessoryCircular)

struct LockWidgetView: View {
    let entry: LifeClipEntry

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .strokeBorder(amber.opacity(0.55), lineWidth: 2)

            VStack(spacing: 2) {
                // Record dot
                Circle()
                    .fill(amber)
                    .frame(width: 10, height: 10)
                Text("REC")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(amber)
            }
        }
        .widgetURL(entry.snapshot.map { recordURL(for: $0.id) })
    }
}

// MARK: - Widget configurations

// Home-screen widget (small + medium)
struct LifeClipHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LifeClipHomeWidget", provider: LifeClipProvider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(
                    Color(red: 0.051, green: 0.051, blue: 0.051),
                    for: .widget
                )
        }
        .configurationDisplayName("LifeClip")
        .description("Tap to record a clip into your latest project.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// Lock-screen widget (circular)
struct LifeClipLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LifeClipLockWidget", provider: LifeClipProvider()) { entry in
            LockWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("LifeClip · REC")
        .description("Quick-record into your latest project from the Lock Screen.")
        .supportedFamilies([.accessoryCircular])
    }
}

// Bundle — registers both widgets
@main
struct LifeClipWidgetBundle: WidgetBundle {
    var body: some Widget {
        LifeClipHomeWidget()
        LifeClipLockWidget()
    }
}

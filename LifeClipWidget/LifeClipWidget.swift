import WidgetKit
import SwiftUI

// MARK: - Shared data model (mirrors WidgetDataStore.Snapshot)

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
        // Never auto-reload — main app calls WidgetCenter.reloadAllTimelines()
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Colours (mirrors Theme, no dependency on main app module)

private let bgColor    = Color(red: 0.051, green: 0.051, blue: 0.051)
private let filmColor  = Color(red: 0.122, green: 0.122, blue: 0.122)
private let amberColor = Color(red: 0.941, green: 0.529, blue: 0.227)
private let inkColor   = Color(red: 0.102, green: 0.102, blue: 0.102)

// MARK: - Deep-link URL helper

private func recordURL(for id: String) -> URL {
    URL(string: "lifeclip://record/\(id)")!
}

// MARK: - Widget Views

struct LifeClipWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: LifeClipEntry

    var body: some View {
        switch family {
        case .systemSmall:  smallView
        case .systemMedium: mediumView
        default:            smallView
        }
    }

    // MARK: Small

    private var smallView: some View {
        ZStack {
            bgColor
            VStack(alignment: .leading, spacing: 0) {
                // App label
                Text("LIFECLIP")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.3))

                Spacer()

                // Project name
                if let snap = entry.snapshot {
                    Text(snap.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text("\(snap.clipCount) clip\(snap.clipCount == 1 ? "" : "s")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 2)
                } else {
                    Text("No project yet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                // Record button
                recordButton(compact: true)
            }
            .padding(14)
        }
        .widgetURL(entry.snapshot.map { recordURL(for: $0.id) })
    }

    // MARK: Medium

    private var mediumView: some View {
        ZStack {
            bgColor
            HStack(spacing: 0) {
                // Thumbnail pane
                thumbnailPane
                    .frame(maxWidth: .infinity)

                // Info pane
                VStack(alignment: .leading, spacing: 0) {
                    Text("LIFECLIP")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.3))

                    Spacer()

                    if let snap = entry.snapshot {
                        Text(snap.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text("\(snap.clipCount) clips · \(durationLabel(snap.totalDuration))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 3)
                    } else {
                        Text("Open LifeClip\nto get started")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(2)
                    }

                    Spacer()
                    recordButton(compact: false)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
            }
        }
        .widgetURL(entry.snapshot.map { recordURL(for: $0.id) })
    }

    // MARK: Sub-views

    @ViewBuilder
    private var thumbnailPane: some View {
        if let snap = entry.snapshot,
           let data = snap.thumbnailData,
           let uiImg = UIImage(data: data) {
            Image(uiImage: uiImg)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            filmColor
                .overlay(
                    Image(systemName: "film")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.15))
                )
        }
    }

    private func recordButton(compact: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.white.opacity(0.85))
                .frame(width: 7, height: 7)
            Text(compact ? "REC" : "Record Clip")
                .font(.system(size: compact ? 13 : 14, weight: .semibold))
                .foregroundStyle(inkColor)
        }
        .padding(.horizontal, compact ? 12 : 14)
        .padding(.vertical, compact ? 8 : 9)
        .background(amberColor, in: Capsule())
    }

    private func durationLabel(_ t: Double) -> String {
        guard t > 0 else { return "0s" }
        return t < 60
            ? String(format: "%.0fs", t)
            : String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - Widget configuration

@main
struct LifeClipWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LifeClipWidget", provider: LifeClipProvider()) { entry in
            LifeClipWidgetView(entry: entry)
                .containerBackground(bgColor, for: .widget)
        }
        .configurationDisplayName("LifeClip")
        .description("Tap to record a clip into your latest project.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

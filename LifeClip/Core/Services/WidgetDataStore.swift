import Foundation
import WidgetKit

// Writes the "last active project" snapshot to the shared App Group so the
// widget can display it without accessing SwiftData directly.
enum WidgetDataStore {
    static let groupID = "group.com.lifeclip.app"
    static let key     = "lastProject"

    struct Snapshot: Codable {
        let id: String
        let name: String
        let clipCount: Int
        let totalDuration: Double
        let thumbnailData: Data?
    }

    static func save(project: Project) {
        let snap = Snapshot(
            id: project.id.uuidString,
            name: project.name,
            clipCount: project.activeClips.count,
            totalDuration: project.totalDuration,
            thumbnailData: project.coverThumbnailData
        )
        guard let defaults = UserDefaults(suiteName: groupID),
              let data = try? JSONEncoder().encode(snap) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> Snapshot? {
        guard let defaults = UserDefaults(suiteName: groupID),
              let data = defaults.data(forKey: key),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        return snap
    }
}

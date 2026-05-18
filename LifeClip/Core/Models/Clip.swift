import Foundation
import SwiftData

@Model
final class Clip {
    var id: UUID
    var createdAt: Date
    var duration: Double
    // Stored as bookmark data so the URL survives app restarts across sandboxed containers
    var fileBookmark: Data?
    var fileURLString: String
    var order: Int
    var isDeleted: Bool
    var deletedAt: Date?
    var thumbnailData: Data?

    @Relationship(inverse: \Project.clips)
    var project: Project?

    init(fileURL: URL, duration: Double, order: Int = 0) {
        self.id = UUID()
        self.createdAt = Date()
        self.duration = duration
        self.fileURLString = fileURL.absoluteString
        self.order = order
        self.isDeleted = false
        self.fileBookmark = try? fileURL.bookmarkData(options: .minimalBookmark)
    }

    /// Resolves the stored URL, preferring the security-scoped bookmark when available.
    var fileURL: URL {
        if let bookmark = fileBookmark {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) {
                return resolved
            }
        }
        return URL(string: fileURLString) ?? URL(fileURLWithPath: fileURLString)
    }

    /// True when the underlying file still exists on disk.
    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Moves the clip to the soft-delete trash. Permanent removal happens after 30 days.
    func softDelete() {
        isDeleted = true
        deletedAt = Date()
    }

    /// Restores the clip from the trash.
    func restore() {
        isDeleted = false
        deletedAt = nil
    }

    /// Copies this clip's video file to a new location and inserts a new Clip
    /// into `targetProject`. File and model record are fully independent —
    /// deleting one will not affect the other.
    func copy(into targetProject: Project, context: ModelContext) {
        let src = fileURL
        let ext = src.pathExtension.isEmpty ? "mov" : src.pathExtension
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dst = docs.appendingPathComponent(UUID().uuidString + "." + ext)
        do {
            try FileManager.default.copyItem(at: src, to: dst)
        } catch {
            return
        }
        let newClip = Clip(fileURL: dst, duration: duration, order: targetProject.activeClips.count)
        newClip.thumbnailData = thumbnailData
        newClip.project = targetProject
        targetProject.updatedAt = Date()
        context.insert(newClip)
    }
}

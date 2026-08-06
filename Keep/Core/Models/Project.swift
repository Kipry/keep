import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date = Date()
    /// In the trash. NOT called `isDeleted`: `PersistentModel` declares an
    /// `isDeleted` of its own, and a stored property of that name shadows the
    /// protocol's — so SwiftData's own machinery would have been reading our
    /// trash flag whenever it asked whether the object was deleted.
    /// `originalName` renames the existing column instead of dropping it, so
    /// nothing already in the trash comes back.
    @Attribute(originalName: "isDeleted")
    var isTrashed: Bool
    var deletedAt: Date?
    var isArchived: Bool = false
    var coverThumbnailData: Data?
    /// Which clip the cover was rendered from, so it can be re-rendered later
    /// (a sharper size, a different crop) without guessing. Nil for projects
    /// whose cover predates this field.
    var coverClipID: UUID? = nil

    @Relationship(deleteRule: .cascade)
    var clips: [Clip]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isTrashed = false
        self.isArchived = false
        self.clips = []
    }

    /// Active (non-deleted) clips sorted by their intended playback order.
    var activeClips: [Clip] {
        clips
            .filter { !$0.isTrashed }
            .sorted { $0.order < $1.order }
    }

    /// Total duration of all active clips in seconds, as they will actually
    /// play — `effectiveDuration` accounts for trims and photo display time.
    /// Summing raw `duration` here made the project header disagree with both
    /// the widget and the finished export.
    var totalDuration: Double {
        activeClips.reduce(0) { $0 + $1.effectiveDuration }
    }

    func softDelete() {
        isTrashed = true
        deletedAt = Date()
    }

    func restore() {
        isTrashed = false
        deletedAt = nil
    }

    func archive() {
        isArchived = true
    }

    func unarchive() {
        isArchived = false
    }
}

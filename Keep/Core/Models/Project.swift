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

    /// A full, independent copy of this project.
    ///
    /// Independent is the point: `Clip.copy(into:context:)` duplicates the
    /// video file on disk as well as the record, so trimming, reordering or
    /// deleting in one project never reaches the other. That costs storage —
    /// the alternative (sharing files between projects) would mean deleting a
    /// clip in the copy silently breaking the original.
    @discardableResult
    func duplicate(context: ModelContext) -> Project {
        let clone = Project(name: String(localized: "\(name) Copy"))
        context.insert(clone)

        // In `activeClips` order, so the copy's filmstrip reads exactly like
        // this one's. A clip whose file has gone missing is skipped rather
        // than carried over as an unplayable row.
        var newCoverID: UUID?
        for clip in activeClips where clip.copy(into: clone, context: context) {
            if clip.id == coverClipID { newCoverID = clone.activeClips.last?.id }
        }

        // The cover has to point at the *clone's* clip: a `coverClipID` from
        // another project resolves to nothing, and it is exactly what
        // `Clip.softDelete` checks to clear a stale cover when the cover clip
        // is deleted. Projects whose cover predates that field fall back to
        // the first clip, which is where their cover came from.
        clone.coverThumbnailData = coverThumbnailData
        clone.coverClipID = coverThumbnailData == nil
            ? nil
            : (newCoverID ?? clone.activeClips.first?.id)
        clone.updatedAt = Date()
        return clone
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

import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date = Date()
    var isDeleted: Bool
    var deletedAt: Date?
    var coverThumbnailData: Data?

    @Relationship(deleteRule: .cascade)
    var clips: [Clip]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isDeleted = false
        self.clips = []
    }

    /// Active (non-deleted) clips sorted by their intended playback order.
    var activeClips: [Clip] {
        clips
            .filter { !$0.isDeleted }
            .sorted { $0.order < $1.order }
    }

    /// Total duration of all active clips in seconds.
    var totalDuration: Double {
        activeClips.reduce(0) { $0 + $1.duration }
    }

    func softDelete() {
        isDeleted = true
        deletedAt = Date()
    }

    func restore() {
        isDeleted = false
        deletedAt = nil
    }
}

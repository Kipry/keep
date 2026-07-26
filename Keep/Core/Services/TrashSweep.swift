import Foundation
import SwiftData

/// Permanently removes trashed clips and projects once the retention window has
/// passed.
///
/// `deletedAt` was written from the very first version but never read, so
/// nothing was ever actually deleted: soft-deleted records — and every one of
/// their video files — accumulated on disk indefinitely, while the delete
/// dialog promised a trash the app had no way to empty. This closes that gap
/// and is what makes the 30-day window in the support docs true.
enum TrashSweep {
    /// Matches the wording in `store/support.md` and the delete confirmations.
    static let retentionDays = 30

    static func run(in context: ModelContext) {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }
        var didChange = false

        // Projects first: deleting one cascades to its clips, so sweeping them
        // up front avoids visiting those clips twice.
        let projects = ((try? context.fetch(FetchDescriptor<Project>())) ?? [])
            .filter { $0.isDeleted && ($0.deletedAt ?? .distantFuture) < cutoff }
        for project in projects {
            for clip in project.clips { clip.deleteFile() }
            context.delete(project)
            didChange = true
        }

        let clips = ((try? context.fetch(FetchDescriptor<Clip>())) ?? [])
            .filter { $0.isDeleted && ($0.deletedAt ?? .distantFuture) < cutoff }
        for clip in clips {
            clip.deleteFile()
            context.delete(clip)
            didChange = true
        }

        if didChange { try? context.save() }
    }

    /// Empties the trash on demand — same file-then-record order as the sweep.
    static func deleteNow(_ clip: Clip, in context: ModelContext) {
        clip.deleteFile()
        context.delete(clip)
        try? context.save()
    }

    static func deleteNow(_ project: Project, in context: ModelContext) {
        for clip in project.clips { clip.deleteFile() }
        context.delete(project)
        try? context.save()
    }
}

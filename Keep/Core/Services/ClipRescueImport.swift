import AVFoundation
import Foundation
import SwiftData

/// One-time recovery pass for clips whose SwiftData record was lost — e.g.
/// after a manual sandbox container transfer that carried the raw video
/// files over but not the (separately-stored) database. Scans Documents for
/// video files no existing Clip points at and creates bare Clip records for
/// them under a single "Wiederhergestellt" project, so the footage isn't
/// silently orphaned on disk. Runs at most once, guarded by a UserDefaults
/// flag — later launches must not re-scan, since legitimately soft-deleted
/// or in-progress files would otherwise be misidentified as orphans.
enum ClipRescueImport {
    private static let didRunKey = "clipRescueImportDidRun"
    private static let videoExtensions: Set<String> = ["mov", "mp4"]

    static func run(in context: ModelContext) async {
        guard !UserDefaults.standard.bool(forKey: didRunKey) else { return }
        UserDefaults.standard.set(true, forKey: didRunKey)

        guard let existingClips = try? context.fetch(FetchDescriptor<Clip>()) else { return }
        let known = Set(existingClips.map { $0.fileURL.standardizedFileURL.path })

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // Exports/ holds compiled project outputs, not raw source clips — skip it.
        let scanFolders = [docs, docs.appendingPathComponent("Clips"), docs.appendingPathComponent("Imports")]

        var orphans: [URL] = []
        for folder in scanFolders {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles
            ) else { continue }
            for url in items where videoExtensions.contains(url.pathExtension.lowercased()) {
                guard !known.contains(url.standardizedFileURL.path) else { continue }
                orphans.append(url)
            }
        }
        guard !orphans.isEmpty else { return }

        let project = Project(name: "Wiederhergestellt")
        context.insert(project)

        var order = 0
        for url in orphans.sorted(by: { creationDate($0) < creationDate($1) }) {
            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else { continue }
            let clip = Clip(fileURL: url, duration: duration, order: order, createdAt: creationDate(url))
            clip.project = project
            context.insert(clip)
            order += 1
        }

        try? context.save()
    }

    private static func creationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
    }
}

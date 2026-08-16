import AVFoundation
import Foundation
import LockedCameraCapture
import SwiftData
import UIKit

// MARK: - Locked capture import

/// Files clips recorded on the Lock Screen into a real project, on the first
/// unlock after they were taken.
///
/// The capture extension cannot do any of this itself: it has no access to the
/// App Group container, and SwiftData's store is unreadable while the device is
/// locked. So it writes a bare `.mov` into its session content directory and
/// stops there. Everything that needs the user's actual data — which project,
/// what order, thumbnail, cover — happens here, in the app, after unlocking.
///
/// That split is the feature, not a limitation to work around: it is exactly
/// why recording can skip the unlock while browsing cannot.
@available(iOS 18.0, *)
enum LockedCaptureImporter {

    /// Drains everything the extension has recorded since the last run.
    ///
    /// Safe to call on every foreground: with nothing pending it does no work
    /// and touches no state. Each session directory is invalidated once its
    /// clips are safely copied and saved, which is what lets the system reclaim
    /// it — skipping that would leave the same clips re-importing forever.
    @MainActor
    static func importPending(context: ModelContext) async {
        let manager = LockedCameraCaptureManager.shared
        let sessions = manager.sessionContentURLs
        guard !sessions.isEmpty else { return }

        var importedAny = false
        for sessionURL in sessions {
            let movies = movieFiles(in: sessionURL)
            for movie in movies {
                if await importClip(from: movie, context: context) { importedAny = true }
            }
            // Invalidate whether or not anything was found: an empty or
            // unreadable session directory is finished business either way, and
            // leaving it behind means walking it again on every launch.
            try? await manager.invalidateSessionContent(at: sessionURL)
        }

        guard importedAny else { return }
        do { try context.save() } catch { return }
        WidgetDataStore.refresh(context: context)
    }

    // MARK: Pieces

    private static func movieFiles(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "mov" }
            // Oldest first, so a burst of locked clips keeps its real order.
            .sorted { creationDate(of: $0) < creationDate(of: $1) }
    }

    /// When the clip was actually recorded — not when it was imported.
    ///
    /// This matters more here than anywhere else in the app: a clip shot at
    /// 23:40 and unlocked the next morning belongs to the night before, in the
    /// diary, in the streak and in the year spiral. Falling back to "now" would
    /// silently file it on the wrong day.
    private static func creationDate(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        return values?.creationDate ?? Date()
    }

    @MainActor
    private static func importClip(from source: URL, context: ModelContext) async -> Bool {
        let recordedAt = creationDate(of: source)

        // Copy out of the session directory before anything else — that
        // directory is the system's to delete, and we're about to tell it we're
        // done with it.
        guard let destination = copyIntoClipsDirectory(source) else { return false }

        let asset = AVURLAsset(url: destination)
        guard let duration = try? await asset.load(.duration),
              duration.seconds.isFinite, duration.seconds > 0 else {
            try? FileManager.default.removeItem(at: destination)
            return false
        }

        guard let project = targetProject(in: context) else {
            try? FileManager.default.removeItem(at: destination)
            return false
        }

        let order = (project.activeClips.map(\.order).max() ?? -1) + 1
        let clip = Clip(fileURL: destination, duration: duration.seconds,
                        order: order, createdAt: recordedAt)
        clip.project = project
        project.updatedAt = Date()
        context.insert(clip)

        // No location: the phone may have travelled between recording and
        // unlocking, and the extension can't capture one. A wrong pin on the
        // map is worse than no pin.
        await attachArtwork(to: clip, in: project, url: destination)
        await ClipAudioLevels.analyzeIfNeeded(clip)
        ClipTone.analyzeIfNeeded(clip)
        return true
    }

    private static func copyIntoClipsDirectory(_ source: URL) -> URL? {
        guard let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let clips = docs.appendingPathComponent("Clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: clips, withIntermediateDirectories: true)
        let destination = clips
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.pathExtension.isEmpty ? "mov" : source.pathExtension)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// Where a locked clip lands: the project the user was most recently in.
    ///
    /// The extension shows this same project's name before recording (handed
    /// over through the intent's app context), so the destination is never a
    /// surprise. If there is genuinely nowhere to put it — a fresh install
    /// where someone reached for the Lock Screen first — a project is created
    /// rather than dropping the clip.
    private static func targetProject(in context: ModelContext) -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { !$0.isTrashed && !$0.isArchived },
            sortBy: [SortDescriptor(\Project.updatedAt, order: .reverse)]
        )
        if let existing = try? context.fetch(descriptor), let first = existing.first {
            return first
        }
        let fresh = Project(name: String(localized: "My Clips"))
        context.insert(fresh)
        return fresh
    }

    /// Thumbnail for the filmstrip, plus the project cover when this is the
    /// first clip — mirrors what the in-app recording path does, so a locked
    /// clip is indistinguishable from any other once it's in.
    @MainActor
    private static func attachArtwork(to clip: Clip, in project: Project, url: URL) async {
        let composer = VideoComposer()
        guard let image = await composer.thumbnail(from: url, maxEdge: Cover.maxEdge) else { return }
        clip.thumbnailData = downscaled(image, maxEdge: 320).jpegData(compressionQuality: 0.7)
        if project.activeClips.count == 1 {
            project.coverThumbnailData = Cover.cropped(image)
                .jpegData(compressionQuality: Cover.quality)
            project.coverClipID = clip.id
        }
    }

    private static func downscaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - App context upkeep

/// Keeps the capture extension's one window into the app current.
///
/// Called whenever the destination or the recording length could have changed,
/// so the Lock Screen never advertises a project that has since been renamed,
/// archived or deleted.
@available(iOS 18.0, *)
enum LockedCaptureContextWriter {
    @MainActor
    static func refresh(context: ModelContext) async {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { !$0.isTrashed && !$0.isArchived },
            sortBy: [SortDescriptor(\Project.updatedAt, order: .reverse)]
        )
        let name = (try? context.fetch(descriptor))?.first?.name
        let stored = UserDefaults.standard.object(forKey: "defaultRecordingDuration") as? Double
        let duration = RecordingDuration.resolve(stored ?? RecordingDuration.standard)
        try? await KeepCaptureIntent.updateAppContext(
            KeepCaptureContext(projectName: name, duration: duration)
        )
    }
}

// AppIntents is needed for `KeepCaptureIntent.updateAppContext(_:)` — that
// member is declared on the CameraCaptureIntent protocol, and this project
// enables MEMBER_IMPORT_VISIBILITY, so the defining module must be imported
// even though the intent type itself lives in this module.
import AppIntents
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

    /// Watches for session content for as long as the app is alive.
    ///
    /// This, not a one-shot read, is the reliable path — and the fix for clips
    /// that only turned up on the *second* launch. Tapping "Open keep." in the
    /// extension hands the app over while the system is still finishing the
    /// handover of the session directory, so `sessionContentURLs` read once at
    /// launch is frequently still empty at that instant. The next launch found
    /// it, which is exactly the "it shows up if I reopen the app" symptom.
    ///
    /// The sequence closes that window: `.initial` covers whatever was already
    /// waiting, `.added` covers anything that lands afterwards, however late.
    @MainActor
    static func observeUpdates(context: ModelContext) async {
        for await update in LockedCameraCaptureManager.shared.sessionContentUpdates {
            switch update {
            case .initial(let urls): await importSessions(urls, context: context)
            case .added(let url):    await importSessions([url], context: context)
            default: break            // `.removed` is the system reclaiming a
                                      // directory we already invalidated.
            }
        }
    }

    /// Drains everything the extension has recorded since the last run.
    ///
    /// Kept alongside the observer as a belt-and-braces pass on launch and on
    /// every foreground: if the sequence never starts for any reason, clips
    /// still arrive, just a beat later. Double-importing is prevented by
    /// `claimed`, not by the two paths staying out of each other's way.
    @MainActor
    static func importPending(context: ModelContext) async {
        await importSessions(LockedCameraCaptureManager.shared.sessionContentURLs,
                             context: context)
    }

    // MARK: Pieces

    /// Session directories already handed to `importSessions`.
    ///
    /// Two callers can now reach the same directory — the observer's `.initial`
    /// and the launch-time drain, at practically the same moment — and every
    /// step in between is `await`, so they would happily interleave and import
    /// the same clip twice. Claiming is the first thing that happens and it is
    /// synchronous, which is what makes it a real guard rather than a smaller
    /// race. Entries are never released: a directory is invalidated once, and
    /// the system does not hand the same one back.
    @MainActor
    private static var claimed: Set<URL> = []

    @MainActor
    private static func importSessions(_ sessions: [URL], context: ModelContext) async {
        let fresh = sessions.filter { claimed.insert($0).inserted }
        guard !fresh.isEmpty else { return }

        var importedAny = false
        for sessionURL in fresh {
            let movies = movieFiles(in: sessionURL)
            for movie in movies {
                if await importClip(from: movie, context: context) { importedAny = true }
            }
            // Invalidate whether or not anything was found: an empty or
            // unreadable session directory is finished business either way, and
            // leaving it behind means walking it again on every launch.
            //
            // Not awaited. This hands a directory back to the system at the one
            // moment the extension it came from may still be winding down, and
            // how long that takes is not ours to bound. Awaited inline it sat
            // on the main actor mid-launch, holding up the very frames the
            // system was asking for — which is what a launch that comes out of
            // the Lock Screen and then doesn't paint looks like. The clips are
            // already copied and saved by then; nothing after this needs it to
            // have finished.
            Task.detached {
                try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: sessionURL)
            }
            // Let the run loop draw between clips. A burst of locked captures
            // is several file copies and thumbnail renders back to back, all on
            // the main actor because SwiftData lives there.
            await Task.yield()
        }

        guard importedAny else { return }
        do { try context.save() } catch { return }
        WidgetDataStore.refresh(context: context)
    }

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

        // From the sidecar the extension wrote at capture time, never from a
        // fix taken now: the phone may have travelled a long way between
        // recording and unlocking, and a wrong pin is worse than no pin. No
        // sidecar simply means no coordinate — location off, permission never
        // granted, or no fix in time.
        applyLocation(from: source, to: clip)

        await attachArtwork(to: clip, in: project, url: destination)
        await ClipAudioLevels.analyzeIfNeeded(clip)
        ClipTone.analyzeIfNeeded(clip)
        return true
    }

    /// Puts a locked clip on the map.
    ///
    /// `geocodeIfNeeded` is what makes it indistinguishable from an in-app
    /// clip once it lands — same cache, same rate limiting, same place names.
    /// It also re-checks the *current* setting before geocoding, so a
    /// coordinate captured before the user switched location off never
    /// reaches Apple.
    @MainActor
    private static func applyLocation(from source: URL, to clip: Clip) {
        let sidecar = LockedClipMetadata.url(for: source)
        guard let data = try? Data(contentsOf: sidecar),
              let metadata = try? JSONDecoder().decode(LockedClipMetadata.self, from: data)
        else { return }
        clip.latitude = metadata.latitude
        clip.longitude = metadata.longitude
        LocationService.shared.geocodeIfNeeded(clip)
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
            KeepCaptureContext(projectName: name,
                               duration: duration,
                               locationGranularity: LocationGranularity.current.rawValue)
        )
    }
}

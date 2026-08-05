import AVFoundation
import Foundation
import SwiftData
import UIKit

/// Repairs Clip file references that point at a stale sandbox container path.
///
/// Every recorded/imported file is stored as an *absolute* URL, which bakes
/// in the app's container UUID at record time. That UUID changes whenever
/// the app is reinstalled under a different bundle identifier (e.g. after a
/// rename) or its container is manually transferred to a new install — the
/// old absolute path then points nowhere, even though the file itself was
/// carried over unchanged. This scans for clips whose file is missing and
/// relinks them to the same path relative to "Documents/" inside the
/// *current* container, if a file exists there.
enum ClipFileRepair {
    static func run(in context: ModelContext) {
        guard let clips = try? context.fetch(FetchDescriptor<Clip>()) else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var didChange = false

        for clip in clips {
            if !clip.isAvailable, let relocated = relocate(clip.fileURLString, under: docs) {
                clip.setFile(relocated)
                didChange = true
            }
            if let photoString = clip.photoSourceURLString, !exists(photoString),
               let relocated = relocate(photoString, under: docs) {
                clip.photoSourceURLString = relocated.absoluteString
                didChange = true
            }
        }

        if didChange { try? context.save() }
    }

    private static func exists(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func relocate(_ absoluteString: String, under docs: URL) -> URL? {
        guard let range = absoluteString.range(of: "/Documents/") else { return nil }
        let relative = String(absoluteString[range.upperBound...])
        let candidate = docs.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}

// MARK: - Cover

/// Size of a project's cover image.
///
/// The card draws it at 166 × 196 pt — 496 × 588 px on a 3× screen. It used to
/// be rendered at a 320 px long edge, so a portrait clip produced a 180 × 320
/// image stretched across 496 px of card: a 2.8× upscale, on top of JPEG at
/// 0.70. That is the entire reason the library looked soft.
enum Cover {
    static let maxEdge: CGFloat = 640
    static let quality: CGFloat = 0.85

    /// Below this a stored cover predates the size above and is worth redoing.
    static let staleBelow: CGFloat = 560

    static func isStale(_ data: Data?) -> Bool {
        guard let data, let image = UIImage(data: data) else { return false }
        return max(image.size.width, image.size.height) < staleBelow
    }
}

// MARK: - CoverThumbnailRepair

/// Re-renders project covers that were captured at the old, too-small size.
///
/// Only touches covers whose source clip can be established for certain: the
/// recorded `coverClipID`, or — for projects that predate that field — a clip
/// whose thumbnail bytes are identical to the cover, which is exactly what the
/// automatic "first clip becomes the cover" path produced. A cover chosen by
/// hand before `coverClipID` existed is left alone rather than silently
/// replaced with a different frame; re-picking it refreshes it.
enum CoverThumbnailRepair {
    static func run(in context: ModelContext) async {
        let composer = VideoComposer()
        guard let projects = try? context.fetch(FetchDescriptor<Project>()) else { return }
        var didChange = false

        for project in projects where Cover.isStale(project.coverThumbnailData) {
            guard let source = sourceClip(for: project) else { continue }
            guard source.isAvailable else { continue }
            let offset = CMTime(seconds: source.trimStart, preferredTimescale: 600)
            guard let image = await composer.thumbnail(from: source.fileURL, at: offset,
                                                       maxEdge: Cover.maxEdge),
                  let data = image.jpegData(compressionQuality: Cover.quality) else { continue }
            project.coverThumbnailData = data
            project.coverClipID = source.id
            didChange = true
        }

        if didChange { try? context.save() }
    }

    private static func sourceClip(for project: Project) -> Clip? {
        if let id = project.coverClipID,
           let clip = project.activeClips.first(where: { $0.id == id }) {
            return clip
        }
        // The automatic path assigned the *same* Data to both, so byte equality
        // identifies the source exactly — no guessing, no near-matching.
        if let cover = project.coverThumbnailData,
           let clip = project.activeClips.first(where: { $0.thumbnailData == cover }) {
            return clip
        }
        return nil
    }
}

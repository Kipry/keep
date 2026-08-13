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

    /// Matches `FilmCell`'s own `4/5` — a cover cropped to this reads as the
    /// same fixed shape a clip recorded in the app already has, whatever the
    /// source's own aspect ratio was. Without this, a cover sourced from a
    /// wide/landscape import (a screen recording, a photo from another app)
    /// kept its native aspect in storage, and the library card — which
    /// `scaledToFill`s it into a narrow portrait tile — had to crop it down
    /// to a thin, unrecognisable centre sliver to do it. Not a stretch bug;
    /// the crop itself was just far more extreme than a portrait source ever
    /// needs, and read as "distorted" for it.
    static let aspect: CGFloat = 4.0 / 5.0

    static func isStale(_ data: Data?) -> Bool {
        guard let data, let image = UIImage(data: data) else { return false }
        if max(image.size.width, image.size.height) < staleBelow { return true }
        let ratio = image.size.width / image.size.height
        return abs(ratio - aspect) > 0.05
    }

    /// Center-crops to `aspect` before any resizing/encoding — so the crop
    /// happens once, deliberately, here, instead of being left to whatever
    /// box the image happens to be displayed in later.
    static func cropped(_ image: UIImage) -> UIImage {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return image }
        let current = w / h
        let cropRect: CGRect
        if current > aspect {
            let targetW = h * aspect
            cropRect = CGRect(x: (w - targetW) / 2, y: 0, width: targetW, height: h)
        } else {
            let targetH = w / aspect
            cropRect = CGRect(x: 0, y: (h - targetH) / 2, width: w, height: targetH)
        }
        // UIImage.size is in points; cropping(to:) on the backing CGImage
        // needs pixels.
        let scale = image.scale
        let pixelRect = CGRect(x: cropRect.origin.x * scale, y: cropRect.origin.y * scale,
                               width: cropRect.width * scale, height: cropRect.height * scale)
        guard let cg = image.cgImage?.cropping(to: pixelRect) else { return image }
        return UIImage(cgImage: cg, scale: scale, orientation: image.imageOrientation)
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
                  let data = Cover.cropped(image).jpegData(compressionQuality: Cover.quality) else { continue }
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

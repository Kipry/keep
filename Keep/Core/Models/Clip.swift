import CoreLocation
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
    var trimStart: Double = 0
    var trimEnd: Double? = nil

    // MARK: Photo clips
    // A photo is stored as a short still-image video (so it flows through the
    // exact same composition/playback pipeline as a real clip) plus a reference
    // to the original image so the display duration can be re-rendered later.
    var isPhoto: Bool = false
    var photoDuration: Double = 3.0
    var photoSourceURLString: String? = nil

    // MARK: Location
    // Where the clip was captured. Precision depends on the user's granularity
    // setting ("place" stores coordinates rounded to ~1 km). placeName arrives
    // asynchronously via reverse geocoding and may stay nil.
    var latitude: Double? = nil
    var longitude: Double? = nil
    var placeName: String? = nil

    // MARK: Audio level
    // Cached measurement of the clip's own audio in dBFS, used to level every
    // clip to the same perceived volume during playback and export. Measured
    // once (decoding is cheap for a three-second clip, but not free for a
    // hundred of them) and nil when the clip has no audio to measure.
    // `audioAnalyzed` distinguishes "no audio" from "not looked at yet".
    var audioRMS: Double? = nil
    var audioPeak: Double? = nil
    var audioAnalyzed: Bool = false

    // MARK: Palette tone
    // The clip's thumbnail reduced to one of sixteen film tones, for the year
    // spiral on the Memories tab. Derived once when the thumbnail exists and
    // stored here: the spiral must never decode 365 images while drawing.
    var toneHex: Int? = nil
    var toneAnalyzed: Bool = false

    /// Capture location, when the clip has one.
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Duration actually used in the compiled video (respects trim / photo duration).
    var effectiveDuration: Double {
        if isPhoto { return photoDuration }
        let end = trimEnd ?? duration
        return max(0.1, end - trimStart)
    }

    /// Original still image backing a photo clip (used to re-render its duration).
    var photoSourceURL: URL? {
        guard let s = photoSourceURLString else { return nil }
        return URL(string: s)
    }

    @Relationship(inverse: \Project.clips)
    var project: Project?

    init(fileURL: URL, duration: Double, order: Int = 0, createdAt: Date = Date()) {
        self.id = UUID()
        self.createdAt = createdAt
        self.duration = duration
        self.fileURLString = fileURL.absoluteString
        self.order = order
        self.isDeleted = false
        self.fileBookmark = try? fileURL.bookmarkData(options: .minimalBookmark)
    }

    /// Repoints this clip at a new backing file (e.g. after re-rendering a
    /// photo clip at a new display duration). Refreshes the security bookmark.
    func setFile(_ url: URL) {
        fileURLString = url.absoluteString
        fileBookmark  = try? url.bookmarkData(options: .minimalBookmark)
        // The cached loudness belongs to the old file, not this one.
        audioRMS = nil
        audioPeak = nil
        audioAnalyzed = false
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

    /// Removes this clip's files from disk. Deleting the SwiftData record alone
    /// leaves the video (and a photo clip's source image) orphaned forever —
    /// unreachable but still occupying storage and still inflating the user's
    /// iCloud backup. Call this immediately before deleting the record.
    func deleteFile() {
        try? FileManager.default.removeItem(at: fileURL)
        if let photo = photoSourceURL {
            try? FileManager.default.removeItem(at: photo)
        }
    }

    /// Copies this clip's video file and inserts a new Clip into
    /// `targetProject`. The video files are independent, so deleting one clip
    /// won't affect the other. A photo clip's *source image* is shared by
    /// reference, so re-rendering one copy's display duration affects both.
    ///
    /// Returns false if the file couldn't be copied — callers previously
    /// reported success unconditionally, so a failed copy showed a "Clip
    /// Copied" toast and no clip.
    @discardableResult
    func copy(into targetProject: Project, context: ModelContext) -> Bool {
        let src = fileURL
        let ext = src.pathExtension.isEmpty ? "mov" : src.pathExtension
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        let clipsDir = docs.appendingPathComponent("Clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
        let dst = clipsDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        do {
            try FileManager.default.copyItem(at: src, to: dst)
        } catch {
            return false
        }
        // max+1, matching the recording path — activeClips.count produced
        // duplicate order values whenever the target had soft-deleted clips,
        // making the filmstrip order non-deterministic.
        let nextOrder = (targetProject.activeClips.map(\.order).max() ?? -1) + 1
        let newClip = Clip(fileURL: dst, duration: duration, order: nextOrder, createdAt: createdAt)
        newClip.thumbnailData = thumbnailData
        newClip.trimStart = trimStart
        newClip.trimEnd   = trimEnd
        newClip.isPhoto = isPhoto
        newClip.photoDuration = photoDuration
        newClip.photoSourceURLString = photoSourceURLString
        newClip.latitude = latitude
        newClip.longitude = longitude
        newClip.placeName = placeName
        // Same bytes, same loudness — carry the measurement over rather than
        // paying to decode the copy again.
        newClip.audioRMS = audioRMS
        newClip.audioPeak = audioPeak
        newClip.audioAnalyzed = audioAnalyzed
        newClip.toneHex = toneHex
        newClip.toneAnalyzed = toneAnalyzed
        newClip.project = targetProject
        targetProject.updatedAt = Date()
        context.insert(newClip)
        return true
    }
}

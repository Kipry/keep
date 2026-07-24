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

    /// Copies this clip's video file to a new location and inserts a new Clip
    /// into `targetProject`. File and model record are fully independent —
    /// deleting one will not affect the other.
    func copy(into targetProject: Project, context: ModelContext) {
        let src = fileURL
        let ext = src.pathExtension.isEmpty ? "mov" : src.pathExtension
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let clipsDir = docs.appendingPathComponent("Clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
        let dst = clipsDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        do {
            try FileManager.default.copyItem(at: src, to: dst)
        } catch {
            return
        }
        let newClip = Clip(fileURL: dst, duration: duration, order: targetProject.activeClips.count, createdAt: createdAt)
        newClip.thumbnailData = thumbnailData
        newClip.trimStart = trimStart
        newClip.trimEnd   = trimEnd
        newClip.isPhoto = isPhoto
        newClip.photoDuration = photoDuration
        newClip.photoSourceURLString = photoSourceURLString
        newClip.latitude = latitude
        newClip.longitude = longitude
        newClip.placeName = placeName
        newClip.project = targetProject
        targetProject.updatedAt = Date()
        context.insert(newClip)
    }
}

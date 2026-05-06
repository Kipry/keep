import AVFoundation
import UIKit

// MARK: - Export Quality

enum ExportQuality {
    case p1080, p4K

    var presetName: String {
        switch self {
        case .p1080: return AVAssetExportPreset1920x1080
        case .p4K:   return AVAssetExportPreset3840x2160
        }
    }
}

// MARK: - Composition Error

enum CompositionError: LocalizedError {
    case noClips
    case assetUnreadable(URL)
    case trackInsertionFailed
    case exportSessionFailed
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .noClips:                    return "No clips to compose."
        case .assetUnreadable(let url):   return "Cannot read asset at \(url.lastPathComponent)."
        case .trackInsertionFailed:       return "Failed to insert a track into the composition."
        case .exportSessionFailed:        return "Export session could not be created."
        case .exportCancelled:            return "Export was cancelled."
        }
    }
}

// MARK: - VideoComposer

/// Assembles an ordered list of clip URLs into a single exported video file.
/// Runs entirely off the main actor using async/await.
actor VideoComposer {

    // MARK: Compose + Export

    /// Merges the given URLs in order and exports the result to the app's Documents folder.
    /// Returns the URL of the exported file.
    func compose(clips: [URL], quality: ExportQuality = .p1080) async throws -> URL {
        guard !clips.isEmpty else { throw CompositionError.noClips }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CompositionError.trackInsertionFailed
        }

        var cursor = CMTime.zero

        for url in clips {
            let asset = AVURLAsset(url: url)

            // Load tracks asynchronously (AVFoundation modern async API)
            let assetVideoTracks = try await asset.loadTracks(withMediaType: .video)
            let assetAudioTracks = try await asset.loadTracks(withMediaType: .audio)
            let duration = try await asset.load(.duration)

            guard let sourceVideo = assetVideoTracks.first else {
                throw CompositionError.assetUnreadable(url)
            }

            let timeRange = CMTimeRange(start: .zero, duration: duration)

            do {
                try videoTrack.insertTimeRange(timeRange, of: sourceVideo, at: cursor)
            } catch {
                throw CompositionError.trackInsertionFailed
            }

            // Audio is optional per clip — insert only when present (handles mute clips gracefully)
            if let sourceAudio = assetAudioTracks.first {
                try? audioTrack.insertTimeRange(timeRange, of: sourceAudio, at: cursor)
            }

            cursor = CMTimeAdd(cursor, duration)
        }

        // Mirror the preferred transform of the first clip so portrait videos don't rotate.
        if let firstVideoTrack = try? await AVURLAsset(url: clips[0]).loadTracks(withMediaType: .video).first,
           let preferredTransform = try? await firstVideoTrack.load(.preferredTransform) {
            videoTrack.preferredTransform = preferredTransform
        }

        return try await export(composition: composition, quality: quality)
    }

    // MARK: Thumbnail

    /// Extracts a single frame thumbnail from a video file at the given time offset.
    func thumbnail(from url: URL, at time: CMTime = .zero) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        return try? await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let image {
                    continuation.resume(returning: UIImage(cgImage: image))
                } else {
                    continuation.resume(throwing: error ?? CompositionError.assetUnreadable(url))
                }
            }
        }
    }

    // MARK: - Private

    private func export(composition: AVMutableComposition, quality: ExportQuality) async throws -> URL {
        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: quality.presetName) else {
            throw CompositionError.exportSessionFailed
        }

        let outputURL = makeExportURL()
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        return try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume(returning: outputURL)
                case .cancelled:
                    continuation.resume(throwing: CompositionError.exportCancelled)
                default:
                    continuation.resume(throwing: session.error ?? CompositionError.exportSessionFailed)
                }
            }
        }
    }

    private func makeExportURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
    }
}

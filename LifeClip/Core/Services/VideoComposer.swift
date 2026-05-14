import AVFoundation
import UIKit

// MARK: - Export Quality

enum ExportQuality: String, CaseIterable, Identifiable {
    case p1080 = "1080p"
    case p4K   = "4K"

    var id: String { rawValue }

    var presetName: String {
        switch self {
        case .p1080: return AVAssetExportPreset1920x1080
        case .p4K:   return AVAssetExportPreset3840x2160
        }
    }
}

// MARK: - Transition Style

enum TransitionStyle: String, CaseIterable, Identifiable {
    case cut      = "Cut"
    case crossFade = "Cross Fade"

    var id: String { rawValue }
}

// MARK: - Errors

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

// MARK: - ProgressBox
// Shared mutable value passed across the actor boundary for UI progress polling.
// Declared @unchecked Sendable because reads/writes race, which is acceptable
// for a coarse progress indicator (worst case: one stale frame).

final class ProgressBox: @unchecked Sendable {
    var value: Double = 0
}

// MARK: - VideoComposer

actor VideoComposer {

    // MARK: Public API

    func compose(
        clips: [URL],
        transition: TransitionStyle = .cut,
        quality: ExportQuality = .p1080,
        progressBox: ProgressBox? = nil
    ) async throws -> URL {
        guard !clips.isEmpty else { throw CompositionError.noClips }

        let pairs = try await loadAssets(urls: clips)

        switch transition {
        case .cut:
            return try await composeCut(pairs: pairs, quality: quality, progressBox: progressBox)
        case .crossFade:
            return try await composeCrossFade(pairs: pairs, quality: quality, progressBox: progressBox)
        }
    }

    // MARK: Thumbnail

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

    // MARK: - Cut composition (single track, no overlap)

    private func composeCut(
        pairs: [(AVURLAsset, CMTime)],
        quality: ExportQuality,
        progressBox: ProgressBox?
    ) async throws -> URL {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CompositionError.trackInsertionFailed }

        var cursor = CMTime.zero
        for (asset, duration) in pairs {
            let srcVideos = try await asset.loadTracks(withMediaType: .video)
            let srcAudios = try await asset.loadTracks(withMediaType: .audio)
            guard let srcVideo = srcVideos.first else { throw CompositionError.assetUnreadable(asset.url) }

            let range = CMTimeRange(start: .zero, duration: duration)
            try videoTrack.insertTimeRange(range, of: srcVideo, at: cursor)
            if let srcAudio = srcAudios.first { try? audioTrack.insertTimeRange(range, of: srcAudio, at: cursor) }
            cursor = CMTimeAdd(cursor, duration)
        }

        applyPreferredTransform(to: videoTrack, from: pairs[0].0)
        return try await export(composition: composition, videoComposition: nil,
                                quality: quality, progressBox: progressBox)
    }

    // MARK: - Cross-fade composition (two alternating tracks with opacity ramps)

    private func composeCrossFade(
        pairs: [(AVURLAsset, CMTime)],
        quality: ExportQuality,
        progressBox: ProgressBox?
    ) async throws -> URL {
        let minDuration = pairs.map { $0.1.seconds }.min() ?? 1.0
        let fadeSecs = min(0.5, minDuration / 2)
        let fadeDuration = CMTime(seconds: fadeSecs, preferredTimescale: 600)

        let composition = AVMutableComposition()
        guard let trackA = composition.addMutableTrack(withMediaType: .video,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid),
              let trackB = composition.addMutableTrack(withMediaType: .video,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CompositionError.trackInsertionFailed }

        let videoTracks = [trackA, trackB]
        var clipTimeRanges: [(range: CMTimeRange, trackIndex: Int)] = []
        var cursor = CMTime.zero

        for (index, (asset, duration)) in pairs.enumerated() {
            let srcVideos = try await asset.loadTracks(withMediaType: .video)
            let srcAudios = try await asset.loadTracks(withMediaType: .audio)
            guard let srcVideo = srcVideos.first else { throw CompositionError.assetUnreadable(asset.url) }

            let trackIndex = index % 2
            let destTrack = videoTracks[trackIndex]
            let srcRange = CMTimeRange(start: .zero, duration: duration)

            try destTrack.insertTimeRange(srcRange, of: srcVideo, at: cursor)
            if let srcAudio = srcAudios.first { try? audioTrack.insertTimeRange(srcRange, of: srcAudio, at: cursor) }

            clipTimeRanges.append((CMTimeRange(start: cursor, duration: duration), trackIndex))

            if index < pairs.count - 1 {
                cursor = CMTimeAdd(cursor, CMTimeSubtract(duration, fadeDuration))
            }
        }

        let renderSize = await renderSize(for: pairs[0].0)
        var instructions: [AVMutableVideoCompositionInstruction] = []

        for (i, (clipRange, trackIndex)) in clipTimeRanges.enumerated() {
            let thisTrack = videoTracks[trackIndex]

            if i < clipTimeRanges.count - 1 {
                let nextTrack = videoTracks[clipTimeRanges[i + 1].trackIndex]
                let nonFadeDur = CMTimeSubtract(clipRange.duration, fadeDuration)
                let nonFadeRange = CMTimeRange(start: clipRange.start, duration: nonFadeDur)
                let fadeStart = CMTimeAdd(clipRange.start, nonFadeDur)
                let fadeRange = CMTimeRange(start: fadeStart, duration: fadeDuration)

                if nonFadeDur.seconds > 0 {
                    let instr = AVMutableVideoCompositionInstruction()
                    instr.timeRange = nonFadeRange
                    instr.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: thisTrack)]
                    instructions.append(instr)
                }

                let fadeInstr = AVMutableVideoCompositionInstruction()
                fadeInstr.timeRange = fadeRange

                let outLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: thisTrack)
                outLayer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: fadeRange)

                let inLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: nextTrack)
                inLayer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: fadeRange)

                fadeInstr.layerInstructions = [inLayer, outLayer]
                instructions.append(fadeInstr)
            } else {
                let instr = AVMutableVideoCompositionInstruction()
                instr.timeRange = clipRange
                instr.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: thisTrack)]
                instructions.append(instr)
            }
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = renderSize
        videoComposition.instructions = instructions

        return try await export(composition: composition, videoComposition: videoComposition,
                                quality: quality, progressBox: progressBox)
    }

    // MARK: - Helpers

    private func loadAssets(urls: [URL]) async throws -> [(AVURLAsset, CMTime)] {
        var result: [(AVURLAsset, CMTime)] = []
        for url in urls {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            result.append((asset, duration))
        }
        return result
    }

    private func applyPreferredTransform(to track: AVMutableCompositionTrack, from asset: AVURLAsset) {
        Task {
            if let srcTrack = try? await asset.loadTracks(withMediaType: .video).first,
               let transform = try? await srcTrack.load(.preferredTransform) {
                track.preferredTransform = transform
            }
        }
    }

    private func renderSize(for asset: AVURLAsset) async -> CGSize {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else {
            return CGSize(width: 1080, height: 1920)
        }
        let isPortrait = transform.b == 1.0 || transform.b == -1.0
        return isPortrait ? CGSize(width: size.height, height: size.width) : size
    }

    private func export(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition?,
        quality: ExportQuality,
        progressBox: ProgressBox?
    ) async throws -> URL {
        guard let session = AVAssetExportSession(asset: composition, presetName: quality.presetName) else {
            throw CompositionError.exportSessionFailed
        }
        let outputURL = makeExportURL()
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        if let vc = videoComposition { session.videoComposition = vc }

        return try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch session.status {
                case .completed: continuation.resume(returning: outputURL)
                case .cancelled: continuation.resume(throwing: CompositionError.exportCancelled)
                default:         continuation.resume(throwing: session.error ?? CompositionError.exportSessionFailed)
                }
            }
            // Poll session.progress ~12 fps and write into the shared box.
            if let box = progressBox {
                Task {
                    while session.status != .completed
                            && session.status != .failed
                            && session.status != .cancelled {
                        box.value = Double(session.progress)
                        try? await Task.sleep(nanoseconds: 80_000_000) // 80 ms
                    }
                }
            }
        }
    }

    private func makeExportURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
    }
}

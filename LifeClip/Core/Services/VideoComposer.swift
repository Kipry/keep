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

final class ProgressBox: @unchecked Sendable {
    var value: Double = 0
}

// MARK: - VideoComposer

actor VideoComposer {

    // MARK: Public API

    struct ClipInfo: Sendable {
        let url: URL
        let trimStart: Double
        let trimEnd: Double?
    }

    func compose(
        clips: [ClipInfo],
        transition: TransitionStyle = .cut,
        quality: ExportQuality = .p1080,
        progressBox: ProgressBox? = nil
    ) async throws -> URL {
        guard !clips.isEmpty else { throw CompositionError.noClips }
        let pairs = try await loadAssets(clips: clips)
        switch transition {
        case .cut:
            return try await composeCut(pairs: pairs, quality: quality, progressBox: progressBox)
        case .crossFade:
            // A single clip has nothing to fade into — treat as cut.
            guard pairs.count >= 2 else {
                return try await composeCut(pairs: pairs, quality: quality, progressBox: progressBox)
            }
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

    // MARK: - Cut composition

    private func composeCut(
        pairs: [(AVURLAsset, CMTimeRange)],
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
        for (asset, range) in pairs {
            let srcVideos = try await asset.loadTracks(withMediaType: .video)
            let srcAudios = try await asset.loadTracks(withMediaType: .audio)
            guard let srcVideo = srcVideos.first else { throw CompositionError.assetUnreadable(asset.url) }
            try videoTrack.insertTimeRange(range, of: srcVideo, at: cursor)
            if let a = srcAudios.first { try? audioTrack.insertTimeRange(range, of: a, at: cursor) }
            cursor = CMTimeAdd(cursor, range.duration)
        }

        await applyPreferredTransform(to: videoTrack, from: pairs[0].0)

        // Explicit video composition forces re-encoding for every export.
        // Without it, AVFoundation uses codec passthrough, which throws a
        // FIGSANDBOX error when clips have mixed codecs (HEVC from the camera
        // mixed with H.264 from Photos imports or copied clips).
        let size = await renderSize(for: pairs[0].0)
        let vc = AVMutableVideoComposition()
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        vc.renderSize    = size
        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange       = CMTimeRange(start: .zero, duration: cursor)
        instr.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)]
        vc.instructions = [instr]

        return try await export(composition: composition, videoComposition: vc,
                                quality: quality, progressBox: progressBox)
    }

    // MARK: - Cross-fade composition
    //
    // Clips alternate between trackA (even indices) and trackB (odd indices),
    // overlapping by `fade` seconds so opacity ramps blend them.
    //
    // Timeline for 2 clips D0, D1 with fade f:
    //
    //   trackA  |<──── D0 ────>|
    //   trackB         |<──── D1 ────>|
    //                  ^
    //                D0-f
    //
    // AVMutableVideoCompositionInstruction time ranges MUST be consecutive
    // and non-overlapping. Correct partition:
    //   [0,    D0-f ]  → trackA body
    //   [D0-f, D0   ]  → A→B crossfade
    //   [D0,   D0+D1-f] → trackB body
    //
    // Per clip i:
    //   bodyStart = clipStart + fade  (0 for i==0, skips the incoming fade zone)
    //   bodyEnd   = clipEnd   - fade  (clipEnd for last clip, skips outgoing zone)
    //   fade-out  [clipEnd-fade, clipEnd]  if not last

    private func composeCrossFade(
        pairs: [(AVURLAsset, CMTimeRange)],
        quality: ExportQuality,
        progressBox: ProgressBox?
    ) async throws -> URL {
        let minSecs = pairs.map { $0.1.duration.seconds }.min() ?? 1.0
        let fade    = CMTime(seconds: min(0.4, minSecs * 0.3), preferredTimescale: 600)

        let composition = AVMutableComposition()
        guard let trackA  = composition.addMutableTrack(withMediaType: .video,
                                                         preferredTrackID: kCMPersistentTrackID_Invalid),
              let trackB  = composition.addMutableTrack(withMediaType: .video,
                                                         preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrackA = composition.addMutableTrack(withMediaType: .audio,
                                                             preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrackB = composition.addMutableTrack(withMediaType: .audio,
                                                             preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CompositionError.trackInsertionFailed }

        let vTracks    = [trackA, trackB]
        let aTracks    = [audioTrackA, audioTrackB]
        var clipStarts = [CMTime]()
        var cursor     = CMTime.zero

        for (i, (asset, range)) in pairs.enumerated() {
            let srcVid = try await asset.loadTracks(withMediaType: .video)
            let srcAud = try await asset.loadTracks(withMediaType: .audio)
            guard let v = srcVid.first else { throw CompositionError.assetUnreadable(asset.url) }
            try vTracks[i % 2].insertTimeRange(range, of: v, at: cursor)
            if let a = srcAud.first {
                try? aTracks[i % 2].insertTimeRange(range, of: a, at: cursor)
            }
            clipStarts.append(cursor)
            if i < pairs.count - 1 {
                cursor = CMTimeAdd(cursor, CMTimeSubtract(range.duration, fade))
            }
        }

        // Both video tracks need the preferred transform so portrait clips render correctly.
        await applyPreferredTransform(to: trackA, from: pairs[0].0)
        await applyPreferredTransform(to: trackB, from: pairs[0].0)

        var instructions = [AVMutableVideoCompositionInstruction]()

        for i in 0..<pairs.count {
            let clipStart = clipStarts[i]
            let clipEnd   = CMTimeAdd(clipStart, pairs[i].1.duration)
            let track     = vTracks[i % 2]
            let isFirst   = i == 0
            let isLast    = i == pairs.count - 1

            // Body instruction: skip the fade-in zone (except first clip) and
            // the fade-out zone (except last clip).
            let bodyStart = isFirst ? clipStart : CMTimeAdd(clipStart, fade)
            let bodyEnd   = isLast  ? clipEnd   : CMTimeSubtract(clipEnd, fade)

            if CMTimeCompare(bodyEnd, bodyStart) > 0 {
                let instr = AVMutableVideoCompositionInstruction()
                instr.timeRange = CMTimeRange(start: bodyStart,
                                              duration: CMTimeSubtract(bodyEnd, bodyStart))
                instr.layerInstructions = [
                    AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                ]
                instructions.append(instr)
            }

            // Fade-out instruction into next clip.
            if !isLast {
                let nextTrack = vTracks[(i + 1) % 2]
                let fadeStart = CMTimeSubtract(clipEnd, fade)
                let fadeRange = CMTimeRange(start: fadeStart, duration: fade)

                let outLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                outLayer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: fadeRange)

                let inLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: nextTrack)
                inLayer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: fadeRange)

                let fadeInstr = AVMutableVideoCompositionInstruction()
                fadeInstr.timeRange       = fadeRange
                fadeInstr.layerInstructions = [inLayer, outLayer]
                instructions.append(fadeInstr)
            }
        }

        let size = await renderSize(for: pairs[0].0)
        let vc   = AVMutableVideoComposition()
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        vc.renderSize    = size
        vc.instructions  = instructions

        return try await export(composition: composition, videoComposition: vc,
                                quality: quality, progressBox: progressBox)
    }

    // MARK: - Helpers

    private func loadAssets(clips: [ClipInfo]) async throws -> [(AVURLAsset, CMTimeRange)] {
        var result = [(AVURLAsset, CMTimeRange)]()
        for info in clips {
            let asset = AVURLAsset(url: info.url)
            // Use the video track's actual time range as the ceiling — the container
            // duration (asset.load(.duration)) is often a few ms longer due to AAC
            // encoder padding, which causes insertTimeRange to throw.
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                throw CompositionError.assetUnreadable(info.url)
            }
            let trackRange = try await videoTrack.load(.timeRange)
            let trackEnd   = CMTimeRangeGetEnd(trackRange)

            let start  = CMTime(seconds: info.trimStart, preferredTimescale: 600)
            let rawEnd = info.trimEnd.map { CMTime(seconds: $0, preferredTimescale: 600) } ?? trackEnd
            let end    = CMTimeMinimum(rawEnd, trackEnd)
            let range  = CMTimeRange(start: start, duration: CMTimeSubtract(end, start))
            result.append((asset, range))
        }
        return result
    }

    // Awaited so the transform is set before export begins (a fire-and-forget
    // Task would race with AVAssetExportSession startup).
    private func applyPreferredTransform(to track: AVMutableCompositionTrack,
                                         from asset: AVURLAsset) async {
        if let src = try? await asset.loadTracks(withMediaType: .video).first,
           let t   = try? await src.load(.preferredTransform) {
            track.preferredTransform = t
        }
    }

    private func renderSize(for asset: AVURLAsset) async -> CGSize {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size  = try? await track.load(.naturalSize),
              let xform = try? await track.load(.preferredTransform) else {
            return CGSize(width: 1080, height: 1920)
        }
        let isPortrait = xform.b == 1.0 || xform.b == -1.0
        return isPortrait ? CGSize(width: size.height, height: size.width) : size
    }

    private func export(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition?,
        quality: ExportQuality,
        progressBox: ProgressBox?
    ) async throws -> URL {
        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: quality.presetName) else {
            throw CompositionError.exportSessionFailed
        }
        let outputURL = makeExportURL()
        session.outputURL                   = outputURL
        session.outputFileType              = .mp4
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
            if let box = progressBox {
                Task {
                    while session.status != .completed
                            && session.status != .failed
                            && session.status != .cancelled {
                        box.value = Double(session.progress)
                        try? await Task.sleep(nanoseconds: 80_000_000)
                    }
                }
            }
        }
    }

    private func makeExportURL() -> URL {
        let docs   = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
    }
}

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
        case .noClips:                    return String(localized: "No clips to compose.")
        case .assetUnreadable(let url):   return String(localized: "Cannot read asset at \(url.lastPathComponent).")
        case .trackInsertionFailed:       return String(localized: "Failed to insert a track into the composition.")
        case .exportSessionFailed:        return String(localized: "Export session could not be created.")
        case .exportCancelled:            return String(localized: "Export was cancelled.")
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

    // MARK: - Still image → video

    /// Renders a still image into a short silent H.264 video of `duration` seconds
    /// so a photo can flow through the same composition pipeline as a real clip.
    /// Returns the URL of the generated `.mov` in the Imports directory.
    func renderStillVideo(from imageURL: URL, duration: Double) async throws -> URL {
        guard let image = UIImage(contentsOfFile: imageURL.path) else {
            throw CompositionError.assetUnreadable(imageURL)
        }
        let size = stillRenderSize(for: image)
        let outURL = makeStillURL()

        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  size.width,
            AVVideoHeightKey: size.height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String:  size.width,
                kCVPixelBufferHeightKey as String: size.height
            ]
        )
        guard writer.canAdd(input) else { throw CompositionError.exportSessionFailed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CompositionError.exportSessionFailed }
        writer.startSession(atSourceTime: .zero)

        guard let buffer = pixelBuffer(from: image, size: size) else {
            writer.cancelWriting()
            throw CompositionError.assetUnreadable(imageURL)
        }

        // A still needs no real frame rate; 12 fps keeps cross-fade ramps smooth.
        let fps = 12
        let totalFrames = max(1, Int((duration * Double(fps)).rounded()))
        for f in 0...totalFrames {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            let pts = CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps))
            adaptor.append(buffer, withPresentationTime: pts)
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? CompositionError.exportSessionFailed
        }
        return outURL
    }

    // Even, capped pixel size for the still video (max 1920 on the long edge).
    private func stillRenderSize(for image: UIImage) -> (width: Int, height: Int) {
        let px = CGSize(width: image.size.width * image.scale,
                        height: image.size.height * image.scale)
        let maxEdge: CGFloat = 1920
        var w = px.width, h = px.height
        guard w > 0, h > 0 else { return (1080, 1920) }
        let longest = max(w, h)
        if longest > maxEdge {
            let s = maxEdge / longest
            w *= s; h *= s
        }
        // Round down to even numbers — required by the H.264 encoder.
        let ew = max(2, Int(w.rounded(.down)) & ~1)
        let eh = max(2, Int(h.rounded(.down)) & ~1)
        return (ew, eh)
    }

    private func pixelBuffer(from image: UIImage, size: (width: Int, height: Int)) -> CVPixelBuffer? {
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, size.width, size.height,
                                         kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pb)
        guard status == kCVReturnSuccess, let buffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: size.width, height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        let canvas = CGSize(width: size.width, height: size.height)

        // Use UIImage.size (not cgImage pixel dimensions) so that UIKit's orientation
        // metadata is honoured when computing the aspect ratio.
        let imgAR = image.size.width / image.size.height
        let canAR = canvas.width / canvas.height
        var drawRect = CGRect(origin: .zero, size: canvas)
        if imgAR > canAR {
            let w = canvas.height * imgAR
            drawRect = CGRect(x: (canvas.width - w) / 2, y: 0, width: w, height: canvas.height)
        } else {
            let h = canvas.width / imgAR
            drawRect = CGRect(x: 0, y: (canvas.height - h) / 2, width: canvas.width, height: h)
        }

        // Render through UIGraphicsImageRenderer at 1:1 pixel scale so UIKit's
        // coordinate system (top-left origin) correctly applies image orientation.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        guard let cg = UIGraphicsImageRenderer(size: canvas, format: format).image { uiCtx in
            UIColor.black.setFill()
            uiCtx.fill(CGRect(origin: .zero, size: canvas))
            image.draw(in: drawRect)
        }.cgImage else { return nil }

        // CGContext has a bottom-left origin, opposite to UIKit. Flip the y-axis
        // before drawing so the rendered CGImage is not upside-down in the buffer.
        ctx.translateBy(x: 0, y: CGFloat(size.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(origin: .zero, size: canvas))

        return buffer
    }

    private func makeStillURL() -> URL {
        let docs   = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("Imports", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
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

        // Using an explicit AVMutableVideoComposition forces re-encoding, which fixes the
        // FIGSANDBOX error for mixed-codec (HEVC + H.264) compositions. Critically,
        // track.preferredTransform is IGNORED when an explicit video composition is used,
        // so we must bake the rotation+scale into each layer instruction explicitly.
        let renderSize = await self.renderSize(for: pairs[0].0)
        let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        var cur = CMTime.zero
        for (asset, range) in pairs {
            let xform = await clipTransform(for: asset, into: renderSize)
            layerInstr.setTransform(xform, at: cur)
            cur = CMTimeAdd(cur, range.duration)
        }

        let vc = AVMutableVideoComposition()
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        vc.renderSize    = renderSize
        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange       = CMTimeRange(start: .zero, duration: cursor)
        instr.layerInstructions = [layerInstr]
        vc.instructions = [instr]

        return try await export(composition: composition, videoComposition: vc,
                                quality: quality, progressBox: progressBox)
    }

    // MARK: - Cross-fade composition

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

        let vTracks = [trackA, trackB]
        let aTracks = [audioTrackA, audioTrackB]
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

        let renderSize = await self.renderSize(for: pairs[0].0)
        var instructions = [AVMutableVideoCompositionInstruction]()

        for i in 0..<pairs.count {
            let clipStart = clipStarts[i]
            let clipEnd   = CMTimeAdd(clipStart, pairs[i].1.duration)
            let track     = vTracks[i % 2]
            let isFirst   = i == 0
            let isLast    = i == pairs.count - 1
            let xform     = await clipTransform(for: pairs[i].0, into: renderSize)

            let bodyStart = isFirst ? clipStart : CMTimeAdd(clipStart, fade)
            let bodyEnd   = isLast  ? clipEnd   : CMTimeSubtract(clipEnd, fade)

            if CMTimeCompare(bodyEnd, bodyStart) > 0 {
                let bodyLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                bodyLayer.setTransform(xform, at: bodyStart)

                let instr = AVMutableVideoCompositionInstruction()
                instr.timeRange = CMTimeRange(start: bodyStart,
                                              duration: CMTimeSubtract(bodyEnd, bodyStart))
                instr.layerInstructions = [bodyLayer]
                instructions.append(instr)
            }

            if !isLast {
                let nextXform = await clipTransform(for: pairs[i + 1].0, into: renderSize)
                let nextTrack = vTracks[(i + 1) % 2]
                let fadeStart = CMTimeSubtract(clipEnd, fade)
                let fadeRange = CMTimeRange(start: fadeStart, duration: fade)

                let outLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                outLayer.setTransform(xform, at: fadeStart)
                outLayer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: fadeRange)

                let inLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: nextTrack)
                inLayer.setTransform(nextXform, at: fadeStart)
                inLayer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: fadeRange)

                let fadeInstr = AVMutableVideoCompositionInstruction()
                fadeInstr.timeRange       = fadeRange
                fadeInstr.layerInstructions = [inLayer, outLayer]
                instructions.append(fadeInstr)
            }
        }

        let vc = AVMutableVideoComposition()
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        vc.renderSize    = renderSize
        vc.instructions  = instructions

        return try await export(composition: composition, videoComposition: vc,
                                quality: quality, progressBox: progressBox)
    }

    // MARK: - Helpers

    private func loadAssets(clips: [ClipInfo]) async throws -> [(AVURLAsset, CMTimeRange)] {
        var result = [(AVURLAsset, CMTimeRange)]()
        for info in clips {
            let asset = AVURLAsset(url: info.url)
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

    // Returns a transform that maps the clip's native video frame into `renderSize`,
    // filling the canvas and centering (crops edges if the aspect ratio doesn't match).
    // When an AVMutableVideoComposition is used, track.preferredTransform is ignored,
    // so the rotation and scale MUST be embedded in the layer instruction.
    private func clipTransform(for asset: AVURLAsset, into renderSize: CGSize) async -> CGAffineTransform {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let preferredTransform = try? await track.load(.preferredTransform) else {
            return .identity
        }
        return transformFilling(naturalSize: naturalSize,
                                preferredTransform: preferredTransform,
                                into: renderSize)
    }

    // Builds a combined transform: preferredTransform → uniform scale to fill canvas → center.
    private func transformFilling(naturalSize: CGSize,
                                  preferredTransform: CGAffineTransform,
                                  into renderSize: CGSize) -> CGAffineTransform {
        // Display dimensions after applying the rotation/flip from preferredTransform.
        // CGSize.applying ignores the translation component and takes absolute values.
        let display = naturalSize.applying(preferredTransform)
        let dw = abs(display.width)
        let dh = abs(display.height)
        guard dw > 0, dh > 0 else { return preferredTransform }

        // Scale to fill: the larger scale dimension fills the canvas; edges are cropped if
        // the aspect ratio differs. Use min() here for letterbox instead.
        let scale = max(renderSize.width / dw, renderSize.height / dh)

        // Center offset: shifts the scaled frame so it's centered in the render canvas.
        let ox = (renderSize.width  - dw * scale) / 2
        let oy = (renderSize.height - dh * scale) / 2

        // Concatenation order: preferredTransform → scale → translate.
        return preferredTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: ox, y: oy))
    }

    // Returns the display-oriented render size for the given asset's first video track.
    // Accounts for the preferredTransform so portrait iPhone videos return (1080, 1920)
    // rather than the raw sensor size (1920, 1080).
    private func renderSize(for asset: AVURLAsset) async -> CGSize {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size  = try? await track.load(.naturalSize),
              let xform = try? await track.load(.preferredTransform) else {
            return CGSize(width: 1080, height: 1920)
        }
        let display = size.applying(xform)
        return CGSize(width: abs(display.width), height: abs(display.height))
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

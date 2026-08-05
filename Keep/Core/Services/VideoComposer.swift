// AVAssetExportSession isn't Sendable, but the progress sequence below has to
// observe it from a child task while the export runs — which is precisely the
// pattern Apple's own iOS 18 API is shaped for.
@preconcurrency import AVFoundation
import UIKit
import QuartzCore

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

    /// Long edge of the exported frame, in pixels.
    ///
    /// The preset alone doesn't decide the output size once an explicit
    /// `AVMutableVideoComposition` is in play — the composition's `renderSize`
    /// does. Building that canvas from this value is what actually makes the
    /// picker mean something.
    var longEdge: CGFloat {
        switch self {
        case .p1080: return 1920
        case .p4K:   return 3840
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
        /// Linear volume factor applied to this clip's audio in the mix, so a
        /// run of clips recorded at wildly different levels plays back evenly.
        /// 1 leaves the recording exactly as captured.
        var gain: Float = 1
        /// The generated intro bumper. It's a bundled asset with a fixed shape,
        /// so it must never be the clip the export canvas takes its shape from.
        var isIntro: Bool = false
    }

    func compose(
        clips: [ClipInfo],
        transition: TransitionStyle = .cut,
        quality: ExportQuality = .p1080,
        progressBox: ProgressBox? = nil
    ) async throws -> URL {
        guard !clips.isEmpty else { throw CompositionError.noClips }
        // loadAssets either returns one entry per clip or throws, so the gains
        // stay index-aligned with the assets.
        let pairs = try await loadAssets(clips: clips)
        let gains = clips.map(\.gain)
        // The canvas takes its shape from the first real clip and its size from
        // the chosen quality. It used to be the first clip's *native* size —
        // which, once the intro bumper was prepended, meant the bundled
        // bumper's size decided the resolution of every export and the quality
        // picker changed nothing.
        let shapeIndex = clips.firstIndex { !$0.isIntro } ?? 0
        let canvas = await canvasSize(for: pairs[shapeIndex].0, quality: quality)
        switch transition {
        case .cut:
            return try await composeCut(pairs: pairs, gains: gains, renderSize: canvas,
                                        quality: quality, progressBox: progressBox)
        case .crossFade:
            guard pairs.count >= 2 else {
                return try await composeCut(pairs: pairs, gains: gains, renderSize: canvas,
                                            quality: quality, progressBox: progressBox)
            }
            return try await composeCrossFade(pairs: pairs, gains: gains, renderSize: canvas,
                                              quality: quality, progressBox: progressBox)
        }
    }

    // MARK: Thumbnail

    /// `maxEdge` is the longest side in pixels. 320 is right for a filmstrip
    /// cell; a project cover is drawn at 166 × 196 pt, which is 496 × 588 px on
    /// a 3× screen, so it needs considerably more.
    func thumbnail(from url: URL, at time: CMTime = .zero,
                   maxEdge: CGFloat = 320) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxEdge, height: maxEdge)
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

        // Use UIImage.size (orientation-aware) so a portrait photo computes a
        // portrait aspect ratio — using cgImage pixel dimensions would swap it
        // and render the frame 90° rotated and stretched.
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

        // A CGBitmapContext has a bottom-left origin (y-up), while UIKit's
        // UIImage.draw expects a top-left origin (y-down). Flip the context first,
        // then draw through UIKit so imageOrientation is honoured AND the frame is
        // stored upright in the pixel buffer (the canonical UIImage→CVPixelBuffer
        // pattern). Drawing a raw CGImage here instead would invert the frame.
        ctx.translateBy(x: 0, y: canvas.height)
        ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: canvas))
        image.draw(in: drawRect)
        UIGraphicsPopContext()

        return buffer
    }

    private func makeStillURL() -> URL {
        let docs   = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("Imports", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
    }

    // MARK: - Intro bumper

    /// Renders the bundled "keep." intro bumper with the project title and its
    /// recording date range burned in near the bottom, ready to be prepended as
    /// the first clip of the final export. Returns nil if the bundled asset is
    /// missing so the caller can fall back to exporting without it.
    func renderBumper(projectName: String, startDate: Date, endDate: Date,
                      quality: ExportQuality) async -> URL? {
        guard let bumperURL = Bundle.main.url(forResource: "BumperIntro", withExtension: "mp4") else { return nil }
        let asset = AVURLAsset(url: bumperURL)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await videoTrack.load(.naturalSize),
              let preferredTransform = try? await videoTrack.load(.preferredTransform),
              let duration = try? await asset.load(.duration)
        else { return nil }

        // At the export's own quality, not a hardcoded 1080p: the bumper is
        // scaled into the final canvas afterwards, and rendering it smaller
        // than that canvas would soften the title card on a 4K export.
        let renderSize = await canvasSize(for: asset, quality: quality)
        guard renderSize.width > 0, renderSize.height > 0 else { return nil }

        // Scale into the canvas rather than using preferredTransform alone: the
        // canvas is now the quality's size, not the bumper's own, so a bare
        // preferredTransform would leave the frame overflowing its bounds.
        let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstr.setTransform(
            transformFilling(naturalSize: naturalSize,
                             preferredTransform: preferredTransform,
                             into: renderSize),
            at: .zero
        )

        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange = CMTimeRange(start: .zero, duration: duration)
        instr.layerInstructions = [layerInstr]

        let vc = AVMutableVideoComposition()
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        vc.renderSize    = renderSize

        // Burn the title card into the bumper via a Core Animation overlay layer
        // composited on top of the decoded video frames.
        let overlay = Self.titleCardImage(
            projectName: projectName,
            rangeLabel: Self.dateRangeLabel(from: startDate, to: endDate),
            size: renderSize
        )
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: renderSize)
        overlayLayer.contents = overlay.cgImage
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)
        vc.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
        vc.instructions = [instr]

        return try? await export(composition: asset, videoComposition: vc,
                                 quality: quality, progressBox: nil)
    }

    private static func dateRangeLabel(from start: Date, to end: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd.MM.yyyy"
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return f.string(from: start)
        }
        return "\(f.string(from: start))  –  \(f.string(from: end))"
    }

    /// Draws the bottom title card (project name + recording date range) as a
    /// transparent overlay image. The title auto-shrinks to fit up to two lines
    /// and gracefully truncates with an ellipsis if it's still too long — so
    /// arbitrarily long project names never overflow or look broken.
    private static func titleCardImage(projectName: String, rangeLabel: String, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { ctx in
            let cg = ctx.cgContext
            let maxWidth   = size.width * 0.86
            let leftInset  = size.width * 0.07
            let bottomInset = size.height * 0.065

            // Bottom scrim so the text stays legible over any bumper content.
            let scrimHeight = size.height * 0.34
            let scrimRect = CGRect(x: 0, y: size.height - scrimHeight, width: size.width, height: scrimHeight)
            let colors = [UIColor.black.withAlphaComponent(0).cgColor,
                         UIColor.black.withAlphaComponent(0.82).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.saveGState()
                cg.clip(to: scrimRect)
                cg.drawLinearGradient(gradient,
                                      start: CGPoint(x: 0, y: scrimRect.minY),
                                      end: CGPoint(x: 0, y: scrimRect.maxY),
                                      options: [])
                cg.restoreGState()
            }

            // Date range — mono, amber, tracked, matching the app's data-label style.
            let rangeFontSize = size.width * 0.032
            let rangeFont = UIFont(name: "JetBrainsMono-Medium", size: rangeFontSize)
                ?? .monospacedSystemFont(ofSize: rangeFontSize, weight: .medium)
            let rangeAttrs: [NSAttributedString.Key: Any] = [
                .font: rangeFont,
                .foregroundColor: UIColor(red: 0.941, green: 0.529, blue: 0.227, alpha: 1),
                .kern: rangeFontSize * 0.09
            ]
            let rangeString = NSAttributedString(string: rangeLabel.uppercased(), attributes: rangeAttrs)
            let rangeSize = rangeString.size()
            let rangeOrigin = CGPoint(x: leftInset, y: size.height - bottomInset - rangeSize.height)
            rangeString.draw(at: rangeOrigin)

            // Title — hand-drawn, prominent. Shrinks in steps until it fits within
            // two lines at `maxWidth`; if it still doesn't fit at the floor size,
            // the final draw call truncates the last line with an ellipsis.
            let maxTitleSize: CGFloat = size.width * 0.115
            let minTitleSize: CGFloat = size.width * 0.05
            var fontSize = maxTitleSize
            var titleFont = UIFont(name: "PatrickHand-Regular", size: fontSize)
                ?? .boldSystemFont(ofSize: fontSize)
            while fontSize > minTitleSize {
                let font = UIFont(name: "PatrickHand-Regular", size: fontSize)
                    ?? .boldSystemFont(ofSize: fontSize)
                let bounding = (projectName as NSString).boundingRect(
                    with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font], context: nil
                )
                titleFont = font
                if bounding.height <= font.lineHeight * 2.05 { break }
                fontSize -= max(1, size.width * 0.003)
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let titleBoxHeight = titleFont.lineHeight * 2.1
            let titleRect = CGRect(
                x: leftInset,
                y: rangeOrigin.y - 6 - titleBoxHeight,
                width: maxWidth,
                height: titleBoxHeight
            )
            NSAttributedString(string: projectName, attributes: titleAttrs)
                .draw(with: titleRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }
    }

    // MARK: - Cut composition

    private func composeCut(
        pairs: [(AVURLAsset, CMTimeRange)],
        gains: [Float],
        renderSize: CGSize,
        quality: ExportQuality,
        progressBox: ProgressBox?
    ) async throws -> URL {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CompositionError.trackInsertionFailed }

        // All clips share one audio track, so the per-clip volume is a step
        // change on that track's mix parameters at each clip's start time.
        let audioParams = AVMutableAudioMixInputParameters(track: audioTrack)
        var isLevelled = false

        var cursor = CMTime.zero
        for (i, (asset, range)) in pairs.enumerated() {
            let srcVideos = try await asset.loadTracks(withMediaType: .video)
            let srcAudios = try await asset.loadTracks(withMediaType: .audio)
            guard let srcVideo = srcVideos.first else { throw CompositionError.assetUnreadable(asset.url) }
            try videoTrack.insertTimeRange(range, of: srcVideo, at: cursor)
            if let a = srcAudios.first {
                try? audioTrack.insertTimeRange(range, of: a, at: cursor)
                let gain = gains[i]
                audioParams.setVolume(gain, at: cursor)
                if gain != 1 { isLevelled = true }
            }
            cursor = CMTimeAdd(cursor, range.duration)
        }

        // Skip the mix entirely when every clip sits at unity — an audio mix
        // that changes nothing is pure overhead for the export session.
        var audioMix: AVMutableAudioMix?
        if isLevelled {
            let mix = AVMutableAudioMix()
            mix.inputParameters = [audioParams]
            audioMix = mix
        }

        // Using an explicit AVMutableVideoComposition forces re-encoding, which fixes the
        // FIGSANDBOX error for mixed-codec (HEVC + H.264) compositions. Critically,
        // track.preferredTransform is IGNORED when an explicit video composition is used,
        // so we must bake the rotation+scale into each layer instruction explicitly.
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
                                audioMix: audioMix,
                                quality: quality, progressBox: progressBox)
    }

    // MARK: - Cross-fade composition

    private func composeCrossFade(
        pairs: [(AVURLAsset, CMTimeRange)],
        gains: [Float],
        renderSize: CGSize,
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

        // Audio mix, one set of parameters per alternating track. Two jobs:
        // the per-clip gain that levels the volumes, and a genuine audio
        // cross-fade. Without the latter both clips ran at full volume through
        // the overlap — the picture dissolved while the sound doubled up, which
        // is exactly where a level jump is most audible.
        let audioParams = [AVMutableAudioMixInputParameters(track: audioTrackA),
                           AVMutableAudioMixInputParameters(track: audioTrackB)]
        for i in 0..<pairs.count {
            let params    = audioParams[i % 2]
            let gain      = gains[i]
            let clipStart = clipStarts[i]
            let clipEnd   = CMTimeAdd(clipStart, pairs[i].1.duration)
            // The fade window is capped at 30% of the shortest clip, so a
            // clip's fade-in and fade-out can never overlap each other.
            if i == 0 {
                params.setVolume(gain, at: clipStart)
            } else {
                params.setVolumeRamp(fromStartVolume: 0, toEndVolume: gain,
                                     timeRange: CMTimeRange(start: clipStart, duration: fade))
            }
            if i < pairs.count - 1 {
                params.setVolumeRamp(fromStartVolume: gain, toEndVolume: 0,
                                     timeRange: CMTimeRange(start: CMTimeSubtract(clipEnd, fade),
                                                            duration: fade))
            }
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioParams

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
                                audioMix: audioMix,
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

    // Returns the display-oriented native size of an asset's first video track.
    // Accounts for the preferredTransform so portrait iPhone videos return
    // (1080, 1920) rather than the raw sensor size (1920, 1080).
    private func nativeSize(for asset: AVURLAsset) async -> CGSize {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size  = try? await track.load(.naturalSize),
              let xform = try? await track.load(.preferredTransform) else {
            return CGSize(width: 1080, height: 1920)
        }
        let display = size.applying(xform)
        return CGSize(width: abs(display.width), height: abs(display.height))
    }

    /// The export canvas: the asset's aspect ratio at the size the user asked
    /// for. Portrait footage at 4K therefore renders 2160×3840, not 3840×2160.
    private func canvasSize(for asset: AVURLAsset, quality: ExportQuality) async -> CGSize {
        let native = await nativeSize(for: asset)
        guard native.width > 0, native.height > 0 else {
            return CGSize(width: 1080, height: 1920)
        }
        let long = quality.longEdge
        let raw: CGSize = native.width >= native.height
            ? CGSize(width: long, height: long * native.height / native.width)
            : CGSize(width: long * native.width / native.height, height: long)
        // H.264 and HEVC both require even dimensions.
        return CGSize(width:  max(2, (raw.width  / 2).rounded() * 2),
                      height: max(2, (raw.height / 2).rounded() * 2))
    }

    private func export(
        composition: AVAsset,
        videoComposition: AVMutableVideoComposition?,
        audioMix: AVMutableAudioMix? = nil,
        quality: ExportQuality,
        progressBox: ProgressBox?
    ) async throws -> URL {
        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: quality.presetName) else {
            throw CompositionError.exportSessionFailed
        }
        let outputURL = makeExportURL()
        session.shouldOptimizeForNetworkUse = true
        if let vc = videoComposition { session.videoComposition = vc }
        if let audioMix { session.audioMix = audioMix }

        // iOS 18 replaced exportAsynchronously + polled `status`/`progress`
        // with an async throwing call and a progress sequence. The sequence
        // finishes on its own once the export leaves the exporting state; the
        // cancel in defer only matters if export throws first.
        let progressTask = progressBox.map { box in
            Task {
                for await state in session.states(updateInterval: 0.08) {
                    if case .exporting(let progress) = state {
                        box.value = progress.fractionCompleted
                    }
                }
            }
        }
        defer { progressTask?.cancel() }

        do {
            try await session.export(to: outputURL, as: .mp4)
        } catch is CancellationError {
            throw CompositionError.exportCancelled
        }
        return outputURL
    }

    /// Exports are transient: they exist to be handed to the share sheet, and
    /// nothing in the app ever refers to one again. tmp keeps them out of
    /// iCloud Backup and lets iOS reclaim the space if we don't get to it.
    private func makeExportURL() -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
    }

    /// Deletes finished exports. Until now they were written to
    /// Documents/Exports and never removed, so every export a user ever made
    /// stayed in the app — and in their iCloud Backup. Sweeps that legacy
    /// folder as well as anything left in tmp by an interrupted share.
    static func purgeExports() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folders = [
            docs.appendingPathComponent("Exports", isDirectory: true),
            fm.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        ]
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil) else { continue }
            for url in items { try? fm.removeItem(at: url) }
        }
    }
}

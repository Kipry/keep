// AVAssetReader and its outputs aren't Sendable, but every one of them here is
// created, drained and dropped inside a single non-isolated async call — none
// of them ever crosses an isolation boundary.
@preconcurrency import AVFoundation
import Foundation

// MARK: - Measurement

/// A clip's own audio level, in dBFS (decibels relative to full scale, so all
/// values are ≤ 0). `rms` is the average level and tracks how loud the clip
/// *feels*; `peak` is the single loudest sample and is what limits how far the
/// clip can be lifted before it clips.
struct LoudnessMeasurement: Sendable {
    let rms: Float
    let peak: Float
}

// MARK: - AudioLoudness

/// Measures how loud a clip is and derives the gain that brings it in line with
/// every other clip.
///
/// Clips are recorded seconds apart across weeks — indoors, outdoors, arm's
/// length, across a room — so their levels drift wildly. Playing them back to
/// back means constantly reaching for the volume button. This levels them at
/// playback and export time via an `AVAudioMix`; the recordings on disk are
/// never rewritten, so the correction is always reversible and costs nothing
/// in storage.
enum AudioLoudness {

    /// Target average level. −20 dBFS is the conventional landing zone for
    /// spoken-word material: loud enough to sit comfortably against system
    /// volume, quiet enough to leave headroom for transients.
    static let targetRMS: Float = -20

    /// How far a single clip may be moved. Without a ceiling, a near-silent
    /// clip would have its room tone and hiss lifted into the foreground.
    static let maxBoost: Float = 12
    static let maxCut: Float   = 12

    /// Ceiling the loudest sample must stay under after the gain is applied.
    static let ceiling: Float = -1

    /// Below this the clip is effectively silent (a muted recording, or a photo
    /// clip's empty track). Boosting it would only amplify noise.
    static let silenceFloor: Float = -50

    /// Anything quieter than this is treated as digital silence, which keeps
    /// `log10` away from zero.
    private static let floorAmplitude: Float = 1e-7

    /// Decodes the clip's audio track and returns its average and peak level.
    /// Returns nil when the file has no audio at all (photo clips, muted
    /// imports) or can't be read.
    ///
    /// Not isolated to any actor: called from the main actor it hops to the
    /// concurrent executor, so the synchronous `copyNextSampleBuffer` drain
    /// never blocks the UI.
    static func measure(url: URL) async -> LoudnessMeasurement? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }

        // Decode to 32-bit float PCM in the track's own sample rate and channel
        // layout — no resampling, and no fixed-point conversion to undo.
        let settings: [String: Any] = [
            AVFormatIDKey:               kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey:      32,
            AVLinearPCMIsFloatKey:       true,
            AVLinearPCMIsBigEndianKey:   false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        var sumOfSquares = 0.0
        var sampleCount  = 0.0
        var peak: Float  = 0

        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let byteCount = CMBlockBufferGetDataLength(block)
            let count = byteCount / MemoryLayout<Float>.size
            guard count > 0 else { continue }

            var samples = [Float](repeating: 0, count: count)
            let status = samples.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return kCMBlockBufferBlockAllocationFailedErr }
                return CMBlockBufferCopyDataBytes(block, atOffset: 0,
                                                  dataLength: count * MemoryLayout<Float>.size,
                                                  destination: base)
            }
            guard status == kCMBlockBufferNoErr else { continue }

            for value in samples {
                let magnitude = abs(value)
                if magnitude > peak { peak = magnitude }
                sumOfSquares += Double(value) * Double(value)
            }
            sampleCount += Double(count)
        }

        guard reader.status == .completed, sampleCount > 0 else { return nil }

        let rms = Float((sumOfSquares / sampleCount).squareRoot())
        return LoudnessMeasurement(rms: decibels(rms), peak: decibels(peak))
    }

    /// Linear gain factor that moves `measurement` to the target level, held
    /// inside the boost/cut limits and then pulled back far enough that the
    /// loudest sample stays under the ceiling.
    static func gain(for measurement: LoudnessMeasurement) -> Float {
        guard measurement.rms > silenceFloor else { return 1 }
        var dB = targetRMS - measurement.rms
        dB = min(max(dB, -maxCut), maxBoost)
        // A clip that is already hot gets pushed *down* here even if the line
        // above wanted to lift it — clipping is far more audible than an
        // imperfectly matched level.
        dB = min(dB, ceiling - measurement.peak)
        return pow(10, dB / 20)
    }

    private static func decibels(_ amplitude: Float) -> Float {
        20 * log10(max(amplitude, floorAmplitude))
    }
}

// MARK: - ClipAudioLevels

/// Bridges `AudioLoudness` and the stored clips: measures on first use, caches
/// the result on the `Clip`, and hands back the gains for a composition.
@MainActor
enum ClipAudioLevels {

    static let defaultsKey = "levelAudio"

    /// On by default. `@AppStorage` doesn't write its default value into
    /// `UserDefaults` until the user touches the toggle, so read through
    /// `object(forKey:)` rather than `bool(forKey:)` — the latter would report
    /// `false` for everyone who never opened Settings.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// Linear gain per clip, in the order given. Always returns one entry per
    /// clip so callers can index it alongside their own arrays; every entry is
    /// `1` when levelling is switched off.
    static func gains(for clips: [Clip]) async -> [Float] {
        guard isEnabled else { return Array(repeating: 1, count: clips.count) }
        var result = [Float]()
        result.reserveCapacity(clips.count)
        for clip in clips {
            await analyzeIfNeeded(clip)
            result.append(gain(of: clip))
        }
        return result
    }

    /// Measures a single clip and caches the result. Safe to call repeatedly —
    /// it returns immediately once the clip has been analyzed.
    static func analyzeIfNeeded(_ clip: Clip) async {
        guard !clip.audioAnalyzed else { return }
        // A photo clip's still-video carries no audio track at all, so skip the
        // decode instead of paying for a read that can only come back nil.
        if !clip.isPhoto, clip.isAvailable,
           let measurement = await AudioLoudness.measure(url: clip.fileURL) {
            clip.audioRMS  = Double(measurement.rms)
            clip.audioPeak = Double(measurement.peak)
        }
        clip.audioAnalyzed = true
    }

    /// Cached gain for a clip. Unity when the clip has no measurement — either
    /// it hasn't been analyzed yet or it has no audio to level.
    static func gain(of clip: Clip) -> Float {
        guard isEnabled, let rms = clip.audioRMS, let peak = clip.audioPeak else { return 1 }
        return AudioLoudness.gain(for: LoudnessMeasurement(rms: Float(rms), peak: Float(peak)))
    }
}

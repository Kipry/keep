import AVFoundation
import CoreGraphics

// MARK: - Export Quality

/// Resolution of a finished export.
///
/// Lives in its own file rather than beside `VideoComposer`: `RecordingQuality`
/// (in `CameraService`) maps to it, and `CameraService` is compiled into the
/// locked-capture extension as well. Leaving this type inside `VideoComposer`
/// would have dragged the entire composition/export machinery — `AVAssetExport`,
/// Core Animation title rendering, the bumper — into a sandboxed extension that
/// only ever records a single clip.
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

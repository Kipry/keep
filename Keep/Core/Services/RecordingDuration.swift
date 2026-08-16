import Foundation

// MARK: - Recording duration

/// How long a tap-to-record clip runs, and the one place the choices live.
///
/// The options used to be a `[1.0, 2.0, 3.0, 5.0]` literal written out twice —
/// once in Settings, once in the camera — with nothing tying them together,
/// while `durationLimit == d` compares `Double`s exactly. Two copies of a list
/// that must agree to the bit is a bug waiting for its second edit.
///
/// Lives apart from `CameraService` because it is now genuinely shared domain
/// data rather than a camera detail: Settings picks it, the in-app camera
/// obeys it, and the locked-capture path carries it across the extension
/// boundary in the intent's app context. Keeping it inside `CameraService`
/// would have dragged `AVCaptureSession` into the widget target just to read
/// one number.
enum RecordingDuration {
    /// The golden ratio. One second clips a moment short; two make you wait for
    /// the end of it.
    static let golden: Double = 1.618
    static let options: [Double] = [1, golden, 3, 5]
    static let standard: Double = golden

    /// `Int(d)` would have rendered 1.618 as "1s" — indistinguishable from the
    /// option next to it.
    static func label(_ d: Double) -> String {
        abs(d - golden) < 0.001 ? "φ" : "\(Int(d))s"
    }

    /// Snaps a stored value onto the nearest option.
    ///
    /// This is the migration: 2 s is gone, and anyone who had chosen it would
    /// otherwise open a picker with nothing selected. 2 s lands on φ.
    static func resolve(_ stored: Double) -> Double {
        options.min(by: { abs($0 - stored) < abs($1 - stored) }) ?? standard
    }
}

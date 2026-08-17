import AppIntents
import Foundation

// MARK: - Locked capture intent

/// The one intent that launches recording from outside the app — Control
/// Centre, the Lock Screen, and the Action button all run this.
///
/// Adopting `CameraCaptureIntent` (rather than plain `AppIntent`) is what makes
/// the system route it into the locked-capture extension instead of trying to
/// open the app: that is the entire mechanism behind "record without
/// unlocking". It also makes the intent eligible as a Camera quick action.
///
/// Compiled into all three targets — app, widget, capture extension. Apple's
/// own guidance is explicit that a `CameraCaptureIntent` must be a member of
/// both the app and the extension; the widget needs it too because that is
/// where the control that launches it lives.
@available(iOS 18.0, *)
struct KeepCaptureIntent: CameraCaptureIntent {
    typealias AppContext = KeepCaptureContext

    static let title: LocalizedStringResource = "Record a Clip"
    static let description = IntentDescription(
        "Records a short clip for keep. — straight from the Lock Screen, without unlocking."
    )

    func perform() async throws -> some IntentResult {
        .result()
    }
}

// MARK: - App context

/// The *only* channel the app has to tell the capture extension anything.
///
/// A locked capture extension is denied the App Group container and shared
/// user defaults outright (Apple's deliberate privacy boundary — the same one
/// that makes this feature safe to offer). So none of the app's real state is
/// reachable from in there: not SwiftData, not `@AppStorage`, not the widget
/// snapshot. `CameraCaptureIntent.appContext` is the sanctioned exception, and
/// it is small (a few KB), so this carries only what the extension genuinely
/// needs to render one honest screen.
///
/// Everything here is a *display and behaviour hint*, never a source of truth:
/// the clip itself is always filed by the app on unlock, against live data.
struct KeepCaptureContext: Codable, Sendable {
    /// Shown so the user knows where the clip will land before they record.
    /// Nil when the app has never run or has no projects yet.
    var projectName: String?
    /// The user's chosen recording length, so a locked clip is the same length
    /// as one recorded inside the app. Falls back to the standard duration.
    var duration: Double

    /// `LocationGranularity.rawValue` — precise, place, or off.
    ///
    /// Carried over because the extension has no way to read the setting
    /// itself, and recording a location the user has switched off would be a
    /// straightforward betrayal of what the app promises. Optional, and nil
    /// means *don't*: an app context written before this field existed decodes
    /// with no value, and the safe reading of "I don't know what they chose"
    /// is to record nothing.
    var locationGranularity: String?

    static let fallback = KeepCaptureContext(projectName: nil,
                                             duration: RecordingDuration.standard,
                                             locationGranularity: nil)
}

// MARK: - Clip sidecar

/// What the capture extension knows about a clip that the file itself can't
/// carry — today just where it was taken.
///
/// Written next to the `.mov` in the session directory, because that is the
/// one place both processes can reach: the extension is denied the App Group
/// container, and its own container is erased when the system suspends it.
/// The app reads it during import and then the directory goes away with
/// everything in it.
///
/// It exists at all because the location has to be captured *when the clip is
/// recorded*. Import happens later — after an unlock that might come hours
/// later and a hundred kilometres away — so a fix taken then wouldn't be
/// imprecise, it would be wrong.
struct LockedClipMetadata: Codable, Sendable {
    var latitude: Double
    var longitude: Double

    /// The sidecar that belongs to a given movie: same name, `.json` instead.
    static func url(for movie: URL) -> URL {
        movie.deletingPathExtension().appendingPathExtension("json")
    }
}

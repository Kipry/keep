import ExtensionKit
import Foundation
import LockedCameraCapture
import SwiftUI

// MARK: - Locked capture extension

/// Recording from the Lock Screen, Control Centre or the Action button —
/// without unlocking the phone.
///
/// This runs in a sandbox that is deliberately far more restricted than the
/// widget's: no App Group container, no shared user defaults, no network, and
/// a container that the system erases the moment it suspends the extension.
/// That is the trade Apple makes for letting a third-party camera run on a
/// locked device, and it is also exactly the behaviour keep. wants — a new
/// clip needs no unlock, but nothing already recorded is reachable from here.
///
/// So this target owns *only* the act of recording. It cannot read the
/// project list, cannot write to SwiftData, and never tries: the clip is
/// written to the session's content directory, and `LockedCaptureImporter` in
/// the app files it into a project on the next unlock.
///
/// The scene deliberately points at `LockedCaptureView`, not at Xcode's
/// template `KeepCaptureViewFinder` (a bare `UIImagePickerController`) — that
/// placeholder has been removed. Only one `@main` may exist in the target, so
/// this is the single entry point.
@main
struct KeepCapture: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            LockedCaptureView(session: session)
        }
    }
}

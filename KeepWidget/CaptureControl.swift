import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Locked capture control

/// The control that starts a recording without unlocking — one control, three
/// places: Control Centre, the Lock Screen's customisable slots, and the
/// Action button (iOS 18 lets a control be bound to it, which is what makes
/// "press the side button, record, done" work).
///
/// It runs `KeepCaptureIntent`, and because that intent adopts
/// `CameraCaptureIntent` the system launches the capture *extension* rather
/// than the app — which is the whole trick. The existing REC lock-screen
/// widget is a different thing and stays: it deep-links into a named project
/// and therefore always needed an unlock. This one trades that targeting for
/// not needing one.
@available(iOS 18.0, *)
struct KeepCaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.kipry.keep.app.capture") {
            ControlWidgetButton(action: KeepCaptureIntent()) {
                Label("Record", systemImage: "record.circle.fill")
            }
        }
        .displayName("keep. · Record")
        .description("Record a clip without unlocking.")
    }
}

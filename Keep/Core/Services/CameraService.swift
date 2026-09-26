// AVCaptureSession isn't marked Sendable, but start/stopRunning are documented
// as safe to call off the main thread — which is exactly why they're dispatched
// to a background queue below (they block). @preconcurrency silences those
// module-level Sendable warnings without weakening our own isolation.
@preconcurrency import AVFoundation
import Combine
import UIKit

// MARK: - Recording quality

/// What the camera captures — and, because of that, the ceiling on what an
/// export can meaningfully be. Exporting 1080p footage at 4K quadruples the
/// file without adding a single pixel of detail, so the export screen only
/// offers the choice when there is one.
enum RecordingQuality: String, CaseIterable, Identifiable {
    case p1080 = "1080p"
    case p4K   = "4K"

    static let defaultsKey = "recordingQuality"

    /// 4K by default. `@AppStorage` doesn't write its default into
    /// `UserDefaults` until the user touches the control, so an absent value
    /// has to mean the default here too — which is why this constant is
    /// repeated at each `@AppStorage` site rather than read from one place.
    static var current: RecordingQuality {
        RecordingQuality(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .p4K
    }

    var id: String { rawValue }

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .p1080: return .hd1920x1080
        case .p4K:   return .hd4K3840x2160
        }
    }

    /// Export resolutions worth offering for footage recorded this way.
    var exportChoices: [ExportQuality] {
        switch self {
        case .p1080: return [.p1080]
        case .p4K:   return ExportQuality.allCases
        }
    }
}

// MARK: - Lens stage

/// One fixed step in the lens picker — what the native Camera app shows as
/// 0,5 / 1 / 2.
///
/// `display` is what the user sees and what the UI compares against;
/// `deviceFactor` is the `videoZoomFactor` that actually selects that physical
/// lens on the virtual multi-camera device.
struct LensStage: Identifiable, Equatable {
    let display: CGFloat
    let deviceFactor: CGFloat
    /// "Ultra Wide", "Wide", "Telephoto" — spoken by VoiceOver, never drawn.
    let name: LocalizedStringResource

    var id: CGFloat { deviceFactor }

    static func == (a: LensStage, b: LensStage) -> Bool {
        a.deviceFactor == b.deviceFactor
    }

    /// Native-camera convention: the selected step carries the ×, the others
    /// are bare numbers. Half steps keep one decimal, whole ones drop it.
    func label(isActive: Bool) -> String {
        let number = display < 1 || display != display.rounded()
            ? String(format: "%.1f", display)
            : String(Int(display))
        let localised = number.replacingOccurrences(
            of: ".", with: Locale.current.decimalSeparator ?? "."
        )
        return isActive ? localised + "×" : localised
    }
}

// MARK: - Errors

enum CameraError: LocalizedError {
    case permissionDenied
    case microphoneDenied
    case deviceNotFound
    case audioDeviceNotFound
    case sessionSetupFailed
    case outputSetupFailed
    case audioConnectionMissing
    case recordingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:       return String(localized: "Camera access denied. Enable it in Settings.")
        case .microphoneDenied:       return String(localized: "Microphone access denied. Enable it in Settings.")
        case .deviceNotFound:         return String(localized: "No camera found on this device.")
        case .audioDeviceNotFound:    return String(localized: "No microphone found on this device.")
        case .sessionSetupFailed:     return String(localized: "Could not configure the capture session.")
        case .outputSetupFailed:      return String(localized: "Could not attach a recording output.")
        case .audioConnectionMissing: return String(localized: "Audio track is not connected.")
        case .recordingFailed(let e): return String(localized: "Recording failed: \(e.localizedDescription)")
        }
    }

    /// True for the two cases that require the user to grant access in Settings,
    /// so the UI can show a dedicated permission screen instead of an error banner.
    var isPermissionDenial: Bool {
        switch self {
        case .permissionDenied, .microphoneDenied: return true
        default:                                    return false
        }
    }
}

// MARK: - Camera Position

enum CameraPosition {
    case front, back
    var avPosition: AVCaptureDevice.Position { self == .front ? .front : .back }
}

// MARK: - CameraService

/// Manages the AVCaptureSession lifecycle for recording video clips with audio.
///
/// Uses virtual multi-lens device types (builtInTripleCamera, builtInDualWideCamera, etc.)
/// so that setting videoZoomFactor seamlessly switches physical lenses — exactly like the
/// native Camera app. No manual lens-switch calls needed from the UI layer.
///
/// Root cause of the Glimpse audio bug: AVAudioSession category was set once at
/// app launch and the audio input was never verified before each individual
/// recording start. Fixed by:
///   1. Configuring AVAudioSession before every session start.
///   2. Re-verifying and re-enabling the audio output connection before every recording.
///   3. Never reusing a stopped session.
@MainActor
final class CameraService: NSObject, ObservableObject {

    // MARK: Published state

    @Published var isRunning = false
    @Published var isRecording = false
    @Published var cameraPosition: CameraPosition = .back
    @Published var cameraError: CameraError?
    @Published var lastRecordedURL: URL?
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var displayZoomFactor: CGFloat = 1.0
    @Published var exposureBias: Float = 0
    /// The fixed lens steps this camera actually has. Empty for a single-lens
    /// camera — the front one, and every phone without a second module — which
    /// is what tells the UI to leave the lens picker out entirely.
    @Published var lensStages: [LensStage] = []
    /// How far to turn icons and labels, in degrees, so they read upright the
    /// way the phone is held: 0 upright, 90 turned left onto its side, −90
    /// turned right. The screens themselves stay portrait, like the system
    /// Camera: the layout holds still and only the symbols turn.
    @Published private(set) var controlRotation: Double = 0

    // MARK: Private objects

    /// Tracks which way up the phone is held, for the camera in use. Its
    /// capture angle is stamped on each recording as it starts, so a clip shot
    /// sideways is saved as a landscape video instead of a portrait one with
    /// the picture on its side. Device-bound, so it's rebuilt on a flip.
    private var captureRotation: AVCaptureDevice.RotationCoordinator?
    /// Drives `controlRotation`. Always the back wide camera's, whichever
    /// camera is active: the front camera's angles are mirrored, and the icons
    /// have to turn the same way either way.
    private var controlRotationSource: AVCaptureDevice.RotationCoordinator?
    private var controlRotationObservation: NSKeyValueObservation?

    /// Where finished recordings are written.
    ///
    /// The app leaves this nil and gets its usual `Documents/Clips`. The
    /// locked-capture extension MUST point it at `session.sessionContentURL`:
    /// an extension's own container is erased when the system suspends it, so
    /// anything written to Documents from in there is gone before the app ever
    /// sees it. The session content directory is the one place that survives
    /// and that the app can pick up from after unlocking.
    var outputDirectory: URL?

    /// The `videoZoomFactor` that reads as "1×" to the user.
    ///
    /// On the back camera that is the wide lens's switch-over point, so pinching
    /// below 1× reaches the ultra-wide. On the front camera it is the crop that
    /// reproduces iOS's default framing inside the wider format selected below —
    /// same purpose, same effect: 1× is where it always was, and there is room
    /// underneath it.
    private var displayZoomReference: CGFloat = 1

    /// The Camera Control's zoom slider, held so it can be swapped when the
    /// camera flips — a control is bound to the device it was created with.
    private var zoomControl: AVCaptureControl?
    /// The system calls controls delegate methods here; it must not be the main
    /// queue, which is where the session's own configuration work runs.
    private let controlsQueue = DispatchQueue(label: "keep.capture.controls")

    private(set) var session: AVCaptureSession?
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var recordingContinuation: CheckedContinuation<URL, Error>?

    // MARK: - Session lifecycle

    func startSession(position: CameraPosition = .back) async throws {
        guard session == nil else { return }
        cameraPosition = position

        // Explicitly request camera + microphone access up front. This surfaces a
        // clear, actionable permission-denied error to the UI instead of silently
        // producing a black/silent session, and triggers the system prompt on first use.
        try await ensurePermissions()

        // AVAudioSession must be configured BEFORE the capture session starts.
        // Skipping this is the #1 reason audio is silent on clips 2+.
        //
        // Awaited on the shared audio queue rather than run inline: off the main
        // thread, and — the point — strictly after any deactivation a preview
        // queued on its way out. Run inline, that deactivation could arrive
        // after this and switch the session off under the recording.
        try await AudioSessionQueue.perform { try Self.configureAudioSession() }

        let s = AVCaptureSession()
        // Prevent AVCaptureSession from overwriting our AVAudioSession configuration
        // (it strips .mixWithOthers by default, which pauses background music).
        s.automaticallyConfiguresApplicationAudioSession = false
        s.beginConfiguration()

        let videoInput = try makeVideoInput(position: position)
        guard s.canAddInput(videoInput) else { throw CameraError.sessionSetupFailed }
        s.addInput(videoInput)
        videoDeviceInput = videoInput

        // After the input, not before: canSetSessionPreset answers against the
        // camera actually in use, and the front camera doesn't do 4K on every
        // device. `.high` is the fallback the session used unconditionally
        // before this setting existed — on iPhone that's 1080p, which is why
        // choosing 4K in the export sheet never produced a 4K frame.
        let preset = RecordingQuality.current.sessionPreset
        s.sessionPreset = s.canSetSessionPreset(preset) ? preset : .high

        let audioInput = try makeAudioInput()
        guard s.canAddInput(audioInput) else { throw CameraError.audioDeviceNotFound }
        s.addInput(audioInput)
        audioDeviceInput = audioInput

        let output = AVCaptureMovieFileOutput()
        guard s.canAddOutput(output) else { throw CameraError.outputSetupFailed }
        s.addOutput(output)
        movieOutput = output

        // Explicitly enable the audio connection — AVFoundation does not always
        // do this automatically after the app resumes from background.
        try verifyAudioConnection(on: output)
        enableStabilization(on: output)

        s.commitConfiguration()
        session = s

        installZoomControl(on: s, device: videoInput.device)
        captureRotation = AVCaptureDevice.RotationCoordinator(device: videoInput.device, previewLayer: nil)
        startTrackingControlRotation(fallback: videoInput.device)

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { s.startRunning(); c.resume() }
        }
        isRunning = true

        // Root cause of the black-preview-on-open bug some testers hit: for a
        // virtual multi-lens device (.builtInTripleCamera / .builtInDualWideCamera
        // — the back camera's default candidates), this switches the active
        // physical lens by changing videoZoomFactor. Doing that before the
        // session is running doesn't reliably take, and the preview connection
        // is left pointed at a lens that never actually starts delivering
        // frames — black, until something forces a fresh reconfiguration.
        // switchCamera() already calls this after the session is running,
        // which is exactly why flipping to the front camera "fixed" it: the
        // front camera has no virtual lens to switch (this is a no-op there),
        // and the flip itself reconfigures the session while it's live.
        setDefaultZoom(on: videoInput.device)
    }

    func stopSession() {
        guard let s = session else { return }
        DispatchQueue.global(qos: .userInitiated).async { if s.isRunning { s.stopRunning() } }
        session = nil; videoDeviceInput = nil; audioDeviceInput = nil; movieOutput = nil
        isRunning = false; isRecording = false
        captureRotation = nil
        controlRotationObservation = nil; controlRotationSource = nil
        // Queued, not inline: nothing waits on the release, and running it on
        // the shared queue keeps it ordered against whatever opens next.
        AudioSessionQueue.enqueue {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: - Recording

    func startRecording() async throws -> URL {
        guard let output = movieOutput, !output.isRecording else { return URL(fileURLWithPath: "") }
        // Re-verify audio connection before every clip — direct fix for Glimpse bug.
        try verifyAudioConnection(on: output)
        // Which way up the phone is held right now. The movie output doesn't
        // turn the frames, it records this as the track's orientation — so it
        // costs nothing, and players, thumbnails and the export all read the
        // clip as landscape from then on. Fixed for the length of the clip.
        if let conn = output.connection(with: .video),
           let angle = captureRotation?.videoRotationAngleForHorizonLevelCapture,
           conn.isVideoRotationAngleSupported(angle) {
            conn.videoRotationAngle = angle
        }
        let url = makeTemporaryURL()
        return try await withCheckedThrowingContinuation { continuation in
            recordingContinuation = continuation
            output.startRecording(to: url, recordingDelegate: self)
            Task { @MainActor in self.isRecording = true }
        }
    }

    func stopRecording() { movieOutput?.stopRecording() }

    // MARK: - Front/back flip

    func switchCamera() async throws {
        guard !isRecording, let s = session else { return }
        let newPosition: CameraPosition = cameraPosition == .back ? .front : .back
        let newInput = try makeVideoInput(position: newPosition)
        s.beginConfiguration()
        if let old = videoDeviceInput { s.removeInput(old) }
        guard s.canAddInput(newInput) else { s.commitConfiguration(); throw CameraError.deviceNotFound }
        s.addInput(newInput)
        s.commitConfiguration()
        videoDeviceInput = newInput
        cameraPosition = newPosition
        captureRotation = AVCaptureDevice.RotationCoordinator(device: newInput.device, previewLayer: nil)
        if let out = movieOutput { enableStabilization(on: out) }
        // The old slider still points at the camera that was just removed.
        installZoomControl(on: s, device: newInput.device)
        setDefaultZoom(on: newInput.device)
        // New device starts at 0 EV bias; keep published state in sync.
        try? newInput.device.lockForConfiguration()
        newInput.device.setExposureTargetBias(0, completionHandler: nil)
        newInput.device.unlockForConfiguration()
        exposureBias = 0
    }

    // MARK: - Orientation

    private func startTrackingControlRotation(fallback: AVCaptureDevice) {
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ?? fallback
        let source = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        controlRotationSource = source
        controlRotationObservation = source.observe(\.videoRotationAngleForHorizonLevelCapture,
                                                    options: [.initial, .new]) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            Task { @MainActor in self?.updateControlRotation(captureAngle: angle) }
        }
    }

    /// The back camera's capture angle is 90 held upright, 0 turned left onto
    /// its side and 180 turned right; the icons turn by the difference. Held
    /// upside down (270) changes nothing, as in the system Camera — the icons
    /// keep whichever way they last pointed.
    private func updateControlRotation(captureAngle: CGFloat) {
        switch Int(captureAngle.rounded()) {
        case 90:  controlRotation = 0
        case 0:   controlRotation = 90
        case 180: controlRotation = -90
        default:  break
        }
    }

    // MARK: - Lens stages

    /// The fixed steps this device offers: the ultra-wide if there is one, the
    /// main lens, and 2×.
    ///
    /// The first two come from the hardware — a virtual multi-camera reports
    /// where each lens takes over, and dividing those by where the *wide* lens
    /// starts turns them into the numbers people know. A phone without an
    /// ultra-wide simply has no step below 1.
    ///
    /// The top step is pinned to 2× rather than read from the telephoto, which
    /// is what the system Camera app does and for the same reason: on a phone
    /// whose tele starts at 5×, a step that jumps straight there is too far to
    /// be the everyday "closer". Which lens actually serves 2× is the device's
    /// business — the telephoto where one reaches it, a crop of the main sensor
    /// otherwise — and only affects what VoiceOver calls it.
    private static func lensStages(for device: AVCaptureDevice) -> [LensStage] {
        let lenses = device.constituentDevices
        guard lenses.count > 1 else { return [] }

        var starts: [CGFloat] = [1.0]
        starts += device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        guard starts.count >= lenses.count,
              let wideIndex = lenses.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }),
              starts[wideIndex] > 0
        else { return [] }
        let reference = starts[wideIndex]

        var result: [LensStage] = []
        if wideIndex > 0 {
            result.append(LensStage(display: starts[0] / reference,
                                    deviceFactor: starts[0],
                                    name: Self.lensName(lenses[0].deviceType)))
        }
        result.append(LensStage(display: 1,
                                deviceFactor: reference,
                                name: Self.lensName(.builtInWideAngleCamera)))

        let doubled = reference * 2
        if doubled <= device.maxAvailableVideoZoomFactor {
            let serving = starts.lastIndex { $0 <= doubled + 0.001 } ?? wideIndex
            let type = lenses.indices.contains(serving)
                ? lenses[serving].deviceType
                : AVCaptureDevice.DeviceType.builtInWideAngleCamera
            result.append(LensStage(display: 2, deviceFactor: doubled,
                                    name: Self.lensName(type)))
        }
        return result
    }

    private static func lensName(_ type: AVCaptureDevice.DeviceType) -> LocalizedStringResource {
        switch type {
        case .builtInUltraWideCamera: return "Ultra Wide"
        case .builtInTelephotoCamera: return "Telephoto"
        default:                      return "Wide"
        }
    }

    /// Moves to a fixed step by zooming the virtual device, not by swapping
    /// `AVCaptureDevice`.
    ///
    /// Swapping the device tears the session down and back up, which is a
    /// black frame in the middle of the viewfinder. Changing `videoZoomFactor`
    /// past a switch-over point hands the same session to the other lens, and
    /// `ramp` makes that a move rather than a jump.
    func selectLens(_ stage: LensStage) {
        guard let device = videoDeviceInput?.device else { return }
        let target = max(device.minAvailableVideoZoomFactor,
                         min(stage.deviceFactor, device.maxAvailableVideoZoomFactor))
        try? device.lockForConfiguration()
        device.cancelVideoZoomRamp()
        device.ramp(toVideoZoomFactor: target, withRate: 8)
        device.unlockForConfiguration()
        // Published immediately: the ramp takes a moment, and the bar should
        // mark the step the instant it was chosen, not when the optics catch up.
        currentZoomFactor = target
        displayZoomFactor = target / displayZoomReference
    }

    // MARK: - Camera Control

    /// Puts zoom on the Camera Control, so sliding the button zooms the way it
    /// does in the system Camera app.
    ///
    /// `AVCaptureSystemZoomSlider` is the system's own control: it takes its
    /// range from the active format's `systemRecommendedVideoZoomRange` and
    /// follows the device when that format changes. Its action closure is what
    /// keeps the on-screen zoom readout honest — without it the hardware and
    /// the UI would each believe a different number.
    ///
    /// A delegate is not optional here. Apple: "For a control to become active,
    /// you must set a AVCaptureSessionControlsDelegate on the session." Adding
    /// the slider without one produces a control that exists and does nothing.
    ///
    /// Silently does nothing on hardware without a Camera Control, which is
    /// every phone before the 16.
    private func installZoomControl(on session: AVCaptureSession, device: AVCaptureDevice) {
        guard session.supportsControls else { return }
        session.setControlsDelegate(self, queue: controlsQueue)

        if let existing = zoomControl {
            session.removeControl(existing)
            zoomControl = nil
        }
        // The action is declared `@MainActor @Sendable (CGFloat) -> Void`, so it
        // already arrives on the main actor — no hop, and the readout updates in
        // the same frame the hardware moved.
        let slider = AVCaptureSystemZoomSlider(device: device) { [weak self] factor in
            guard let self else { return }
            self.currentZoomFactor = factor
            self.displayZoomFactor = factor / self.displayZoomReference
        }
        guard session.canAddControl(slider) else { return }
        session.addControl(slider)
        zoomControl = slider
    }

    // MARK: - Zoom (auto-switches lenses via virtual device)

    func setZoom(_ factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }
        let clamped = max(device.minAvailableVideoZoomFactor,
                          min(factor, device.maxAvailableVideoZoomFactor))
        try? device.lockForConfiguration()
        // A ramp from a lens tap would otherwise keep running underneath the
        // finger and fight it.
        device.cancelVideoZoomRamp()
        device.videoZoomFactor = clamped
        device.unlockForConfiguration()
        currentZoomFactor = clamped
        displayZoomFactor = clamped / displayZoomReference
    }

    // MARK: - Focus / Torch

    func focusAt(_ point: CGPoint) {
        guard let device = videoDeviceInput?.device,
              device.isFocusPointOfInterestSupported else { return }
        try? device.lockForConfiguration()
        device.focusPointOfInterest = point
        device.focusMode = .autoFocus
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = point
            device.exposureMode = .autoExpose
        }
        device.unlockForConfiguration()
    }

    func setExposureBias(_ bias: Float) {
        guard let device = videoDeviceInput?.device else { return }
        let clamped = max(device.minExposureTargetBias, min(bias, device.maxExposureTargetBias))
        try? device.lockForConfiguration()
        device.setExposureTargetBias(clamped, completionHandler: nil)
        device.unlockForConfiguration()
        exposureBias = clamped
    }

    func setTorch(_ on: Bool) {
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    // MARK: - Permissions

    /// Verifies camera + microphone authorization, requesting it on first use.
    /// Throws `.permissionDenied` / `.microphoneDenied` when the user has declined,
    /// so the UI can route to a dedicated "Open Settings" screen.
    private func ensurePermissions() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                throw CameraError.permissionDenied
            }
        default: // .denied, .restricted
            throw CameraError.permissionDenied
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw CameraError.microphoneDenied
            }
        default: // .denied, .restricted
            throw CameraError.microphoneDenied
        }
    }

    // MARK: - Private helpers

    // Maps internal videoZoomFactor to the conventional camera-app multiplier.
    // If the device has virtualDeviceSwitchOverVideoZoomFactors, the first entry
    // is where the "1×" lens activates — dividing by it normalises any camera
    // (back triple/dual-wide OR front wide+ultrawide) to the familiar 0.5×/1×/2× scale.
    private func setDefaultZoom(on device: AVCaptureDevice) {
        lensStages = Self.lensStages(for: device)
        // Front camera: widen the format first, then sit at the crop that looks
        // like the old framing. Order matters — the zoom factor below is
        // meaningless until the format it crops is the one in use.
        if device.position == .front, let reference = widenFrontFormat(on: device) {
            displayZoomReference = reference
            let factor = min(reference, device.maxAvailableVideoZoomFactor)
            try? device.lockForConfiguration()
            device.videoZoomFactor = factor
            device.unlockForConfiguration()
            currentZoomFactor = factor
            displayZoomFactor = factor / reference
            return
        }

        guard let wideStart = device.virtualDeviceSwitchOverVideoZoomFactors.first else {
            displayZoomReference = 1
            currentZoomFactor = device.videoZoomFactor
            displayZoomFactor = device.videoZoomFactor
            return
        }
        let factor = CGFloat(truncating: wideStart)
        displayZoomReference = factor
        try? device.lockForConfiguration()
        device.videoZoomFactor = factor
        device.unlockForConfiguration()
        currentZoomFactor = factor
        displayZoomFactor = 1.0
    }

    /// Puts the front camera on the widest format it has, and reports the crop
    /// factor that reproduces the framing it had before.
    ///
    /// The front camera is a single lens: `minAvailableVideoZoomFactor` is 1.0
    /// and there is nothing to zoom out *into*. Its full field of view is only
    /// reachable by choosing a different **format** — and the one iOS picks for
    /// a session preset is cropped, which is why the widest step here was never
    /// as wide as the system Camera app's.
    ///
    /// Only formats with the same dimensions are considered, so the recording
    /// resolution is exactly what the preset would have given. Setting
    /// `activeFormat` does switch the session to input priority, which is why
    /// that guarantee has to come from the filter rather than from the preset.
    ///
    /// Returns nil when nothing wider exists — then the old behaviour stands.
    private func widenFrontFormat(on device: AVCaptureDevice) -> CGFloat? {
        let current = device.activeFormat
        let size = CMVideoFormatDescriptionGetDimensions(current.formatDescription)
        let before = current.videoFieldOfView
        guard before > 0 else { return nil }

        let candidates = device.formats.filter { format in
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard d.width == size.width, d.height == size.height else { return false }
            // A wider frame isn't worth a slideshow: keep 30 fps available.
            return format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
        }
        guard let widest = candidates.max(by: { $0.videoFieldOfView < $1.videoFieldOfView }),
              widest.videoFieldOfView > before + 0.5 else { return nil }

        do {
            try device.lockForConfiguration()
            device.activeFormat = widest
            device.unlockForConfiguration()
        } catch {
            return nil
        }

        // The crop is linear across the sensor, so the factor that restores the
        // old coverage is the ratio of the half-angle tangents — not of the
        // angles themselves, which would drift further the wider the lens.
        let rad = Double.pi / 180
        let ratio = tan(Double(widest.videoFieldOfView) / 2 * rad)
                  / tan(Double(before) / 2 * rad)
        return CGFloat(max(1, ratio))
    }

    /// Static and nonisolated because it runs on `AudioSessionQueue`, not on
    /// the main actor: it touches nothing but the shared audio session.
    nonisolated private static func configureAudioSession() throws {
        let a = AVAudioSession.sharedInstance()
        // .videoRecording, not .measurement.
        //
        // `.measurement` was chosen to disable input DSP (AEC, noise reduction,
        // AGC) for a cleaner recording. But Apple's own description of it is
        // that it "disables system-supplied signal processing for input *and
        // output* signals" — and this session deliberately mixes with other
        // audio, so whatever the user is listening to gets played back through
        // that same unprocessed output. Losing the system's output levelling is
        // heard as music jumping in volume the instant recording starts, which
        // is exactly what was reported.
        //
        // `.videoRecording` is the mode meant for this: it tunes the input for
        // recording video and leaves the output path alone. The recorded audio
        // now carries Apple's standard video-recording processing rather than
        // none at all — a real change in character, and the right trade against
        // shouting into someone's headphones.
        //
        // Bluetooth routing — two profiles with very different behaviour:
        //   • .allowBluetooth     = HFP, a BIDIRECTIONAL profile. Including it lets iOS route
        //     the mic INPUT to AirPods/Bluetooth headsets, which have far worse microphone
        //     quality than the iPhone's built-in mics. Intentionally OMITTED.
        //   • .allowBluetoothA2DP = A2DP, an OUTPUT-ONLY profile (no microphone path at all).
        //     Including it keeps background music playing over connected Bluetooth speakers /
        //     headphones during recording, while the recording itself stays on the built-in mics.
        try a.setCategory(.playAndRecord, mode: .videoRecording,
                          options: [.mixWithOthers, .allowBluetoothA2DP])
        // iOS silences ALL haptics by default while a .playAndRecord session is
        // active (so the taptic buzz can't bleed onto the mic track). Without
        // this opt-in, the record start/stop haptics fire but are suppressed.
        try? a.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try a.setActive(true)
        // Explicitly select the built-in mic so AirPods or other connected accessories
        // can never be chosen as the audio source, regardless of system default routing.
        if let builtInMic = a.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try a.setPreferredInput(builtInMic)
        }
    }

    /// Prefers virtual multi-lens cameras (builtInTripleCamera, builtInDualWideCamera, etc.)
    /// so iOS handles seamless lens switching when videoZoomFactor is changed.
    private func makeVideoInput(position: CameraPosition) throws -> AVCaptureDeviceInput {
        let candidates: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]

        for type in candidates {
            if let device = AVCaptureDevice.default(type, for: .video, position: position.avPosition),
               let input = try? AVCaptureDeviceInput(device: device) {
                return input
            }
        }
        throw CameraError.deviceNotFound
    }

    private func makeAudioInput() throws -> AVCaptureDeviceInput {
        guard let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device) else { throw CameraError.audioDeviceNotFound }
        return input
    }

    private func enableStabilization(on output: AVCaptureMovieFileOutput) {
        guard let conn = output.connection(with: .video),
              conn.isVideoStabilizationSupported else { return }
        conn.preferredVideoStabilizationMode = .cinematicExtended
    }

    private func verifyAudioConnection(on output: AVCaptureMovieFileOutput) throws {
        guard let connection = output.connection(with: .audio) else { throw CameraError.audioConnectionMissing }
        connection.isEnabled = true
    }

    private func makeTemporaryURL() -> URL {
        let clips = outputDirectory ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: clips, withIntermediateDirectories: true)
        return clips.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.isRecording = false
            if let error {
                self.recordingContinuation?.resume(throwing: CameraError.recordingFailed(error))
            } else {
                self.lastRecordedURL = outputFileURL
                self.recordingContinuation?.resume(returning: outputFileURL)
            }
            self.recordingContinuation = nil
        }
    }
}

// MARK: - Camera Control lifecycle

/// Required for the Camera Control's zoom slider to be active at all — the
/// session ignores controls without a delegate. Nothing here needs to react:
/// the slider drives the device directly and reports back through its own
/// action closure. These exist so the control works, and as the place to hook
/// in if the UI should ever step out of the way while the control is on screen.
///
/// No availability guard: the whole app targets iOS 18, so annotating the
/// conformance would only make it conditional for a case that can't occur —
/// and then `setControlsDelegate(self,…)` wouldn't compile.
extension CameraService: AVCaptureSessionControlsDelegate {
    nonisolated func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {}
    nonisolated func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {}
    nonisolated func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {}
    nonisolated func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {}
}

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

    /// 1080p by default. `@AppStorage` doesn't write its default into
    /// `UserDefaults` until the user touches the control, so an absent value
    /// has to mean the default here too.
    static var current: RecordingQuality {
        RecordingQuality(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .p1080
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

    // MARK: Private objects

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
        try configureAudioSession()

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
        setDefaultZoom(on: videoInput.device)

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { s.startRunning(); c.resume() }
        }
        isRunning = true
    }

    func stopSession() {
        guard let s = session else { return }
        DispatchQueue.global(qos: .userInitiated).async { if s.isRunning { s.stopRunning() } }
        session = nil; videoDeviceInput = nil; audioDeviceInput = nil; movieOutput = nil
        isRunning = false; isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Recording

    func startRecording() async throws -> URL {
        guard let output = movieOutput, !output.isRecording else { return URL(fileURLWithPath: "") }
        // Re-verify audio connection before every clip — direct fix for Glimpse bug.
        try verifyAudioConnection(on: output)
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
        if let out = movieOutput { enableStabilization(on: out) }
        setDefaultZoom(on: newInput.device)
        // New device starts at 0 EV bias; keep published state in sync.
        try? newInput.device.lockForConfiguration()
        newInput.device.setExposureTargetBias(0, completionHandler: nil)
        newInput.device.unlockForConfiguration()
        exposureBias = 0
    }

    // MARK: - Zoom (auto-switches lenses via virtual device)

    func setZoom(_ factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }
        let clamped = max(device.minAvailableVideoZoomFactor,
                          min(factor, device.maxAvailableVideoZoomFactor))
        try? device.lockForConfiguration()
        device.videoZoomFactor = clamped
        device.unlockForConfiguration()
        currentZoomFactor = clamped
        displayZoomFactor = Self.computeDisplayZoom(clamped, device: device)
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
        guard let wideStart = device.virtualDeviceSwitchOverVideoZoomFactors.first else {
            currentZoomFactor = device.videoZoomFactor
            displayZoomFactor = Self.computeDisplayZoom(device.videoZoomFactor, device: device)
            return
        }
        let factor = CGFloat(truncating: wideStart)
        try? device.lockForConfiguration()
        device.videoZoomFactor = factor
        device.unlockForConfiguration()
        currentZoomFactor = factor
        displayZoomFactor = 1.0
    }

    private static func computeDisplayZoom(_ factor: CGFloat, device: AVCaptureDevice) -> CGFloat {
        if let first = device.virtualDeviceSwitchOverVideoZoomFactors.first {
            return factor / CGFloat(truncating: first)
        }
        return factor
    }

    private func configureAudioSession() throws {
        let a = AVAudioSession.sharedInstance()
        // .measurement mode disables all DSP (AEC, noise reduction, AGC).
        //
        // Bluetooth routing — two profiles with very different behaviour:
        //   • .allowBluetooth     = HFP, a BIDIRECTIONAL profile. Including it lets iOS route
        //     the mic INPUT to AirPods/Bluetooth headsets, which have far worse microphone
        //     quality than the iPhone's built-in mics. Intentionally OMITTED.
        //   • .allowBluetoothA2DP = A2DP, an OUTPUT-ONLY profile (no microphone path at all).
        //     Including it keeps background music playing over connected Bluetooth speakers /
        //     headphones during recording, while the recording itself stays on the built-in mics.
        try a.setCategory(.playAndRecord, mode: .measurement,
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
        let clips = FileManager.default
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

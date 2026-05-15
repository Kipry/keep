import AVFoundation
import Combine
import UIKit

// MARK: - Errors

enum CameraError: LocalizedError {
    case permissionDenied
    case deviceNotFound
    case audioDeviceNotFound
    case sessionSetupFailed
    case outputSetupFailed
    case audioConnectionMissing
    case recordingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:       return "Camera access denied. Enable it in Settings."
        case .deviceNotFound:         return "No camera found on this device."
        case .audioDeviceNotFound:    return "No microphone found on this device."
        case .sessionSetupFailed:     return "Could not configure the capture session."
        case .outputSetupFailed:      return "Could not attach a recording output."
        case .audioConnectionMissing: return "Audio track is not connected."
        case .recordingFailed(let e): return "Recording failed: \(e.localizedDescription)"
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

        // AVAudioSession must be configured BEFORE the capture session starts.
        // Skipping this is the #1 reason audio is silent on clips 2+.
        try configureAudioSession()

        let s = AVCaptureSession()
        s.beginConfiguration()
        s.sessionPreset = .high

        let videoInput = try makeVideoInput(position: position)
        guard s.canAddInput(videoInput) else { throw CameraError.sessionSetupFailed }
        s.addInput(videoInput)
        videoDeviceInput = videoInput

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
        if newPosition == .back {
            setDefaultZoom(on: newInput.device)
        } else {
            currentZoomFactor = newInput.device.videoZoomFactor
            displayZoomFactor = Self.computeDisplayZoom(newInput.device.videoZoomFactor, device: newInput.device)
        }
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

    func setTorch(_ on: Bool) {
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    // MARK: - Private helpers

    // Maps internal videoZoomFactor to the conventional camera-app multiplier.
    // Devices with an ultra-wide lens (triple / dual-wide): the first switch-over
    // factor is where the wide-angle (1×) activates, so dividing by it gives
    // 0.5× for ultra-wide, 1× for wide, 2-3× for telephoto.
    // Devices without an ultra-wide: factor is used as-is (starts at 1×).
    private func setDefaultZoom(on device: AVCaptureDevice) {
        let hasUltraWide = device.deviceType == .builtInTripleCamera
                        || device.deviceType == .builtInDualWideCamera
        guard hasUltraWide,
              let wideStart = device.virtualDeviceSwitchOverVideoZoomFactors.first else {
            currentZoomFactor = device.videoZoomFactor
            displayZoomFactor = Self.computeDisplayZoom(device.videoZoomFactor, device: device)
            return
        }
        let factor = CGFloat(wideStart)
        try? device.lockForConfiguration()
        device.videoZoomFactor = factor
        device.unlockForConfiguration()
        currentZoomFactor = factor
        displayZoomFactor = 1.0
    }

    private static func computeDisplayZoom(_ factor: CGFloat, device: AVCaptureDevice) -> CGFloat {
        let hasUltraWide = device.deviceType == .builtInTripleCamera
                        || device.deviceType == .builtInDualWideCamera
        if hasUltraWide, let first = device.virtualDeviceSwitchOverVideoZoomFactors.first {
            return factor / CGFloat(first)
        }
        return factor
    }

    private func configureAudioSession() throws {
        let a = AVAudioSession.sharedInstance()
        try a.setCategory(.playAndRecord, mode: .videoRecording,
                          options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
        try a.setActive(true)
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

    private func verifyAudioConnection(on output: AVCaptureMovieFileOutput) throws {
        guard let connection = output.connection(with: .audio) else { throw CameraError.audioConnectionMissing }
        connection.isEnabled = true
    }

    private func makeTemporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
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

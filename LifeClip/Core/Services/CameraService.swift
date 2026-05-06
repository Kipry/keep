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
    var avPosition: AVCaptureDevice.Position {
        self == .front ? .front : .back
    }
}

// MARK: - CameraService

/// Manages the AVCaptureSession lifecycle for recording video clips with audio.
///
/// Root cause of the Glimpse audio bug: AVAudioSession category was set once at
/// app launch and the audio input was never verified before each individual
/// recording start. We fix this by:
///   1. Configuring AVAudioSession.sharedInstance() with .playAndRecord / .videoRecording
///      before every session start.
///   2. Re-verifying and re-enabling the audio connection on the movie output before
///      every call to startRecording(to:).
///   3. Never reusing a stopped session — teardown is explicit and a fresh session
///      is built for each camera-screen visit.
@MainActor
final class CameraService: NSObject, ObservableObject {

    // MARK: Published state

    @Published var isRunning = false
    @Published var isRecording = false
    @Published var cameraPosition: CameraPosition = .back
    @Published var cameraError: CameraError?
    @Published var lastRecordedURL: URL?

    // MARK: Private AVFoundation objects

    private(set) var session: AVCaptureSession?
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var movieOutput: AVCaptureMovieFileOutput?

    private var recordingContinuation: CheckedContinuation<URL, Error>?

    // MARK: - Session lifecycle

    /// Builds and starts a fresh capture session. Call once when the camera screen appears.
    func startSession(position: CameraPosition = .back) async throws {
        guard session == nil else { return }
        cameraPosition = position

        // Step 1 — AVAudioSession must be configured BEFORE the capture session starts.
        // Skipping this is the #1 reason audio is silent on clips 2+.
        try configureAudioSession()

        let s = AVCaptureSession()
        s.beginConfiguration()
        s.sessionPreset = .high

        // Step 2 — Video input
        let videoInput = try makeVideoInput(position: position)
        guard s.canAddInput(videoInput) else { throw CameraError.sessionSetupFailed }
        s.addInput(videoInput)
        videoDeviceInput = videoInput

        // Step 3 — Audio input
        let audioInput = try makeAudioInput()
        guard s.canAddInput(audioInput) else { throw CameraError.audioDeviceNotFound }
        s.addInput(audioInput)
        audioDeviceInput = audioInput

        // Step 4 — Movie file output
        let output = AVCaptureMovieFileOutput()
        guard s.canAddOutput(output) else { throw CameraError.outputSetupFailed }
        s.addOutput(output)
        movieOutput = output

        // Step 5 — Explicitly enable the audio connection on the output.
        // AVFoundation does not always do this automatically, especially after
        // the app resumes from the background.
        try verifyAudioConnection(on: output)

        s.commitConfiguration()
        session = s

        // Run session off the main actor to keep the UI responsive.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                s.startRunning()
                continuation.resume()
            }
        }
        isRunning = true
    }

    /// Stops and tears down the session. Call when the camera screen disappears.
    func stopSession() {
        guard let s = session else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if s.isRunning { s.stopRunning() }
        }
        session = nil
        videoDeviceInput = nil
        audioDeviceInput = nil
        movieOutput = nil
        isRunning = false
        isRecording = false

        // Release the audio session so other apps (music, phone) can use it.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Recording

    /// Starts recording to a temp file and returns the URL when finished.
    func startRecording() async throws -> URL {
        guard let output = movieOutput, !output.isRecording else { return URL(fileURLWithPath: "") }

        // Re-verify the audio connection before every clip — this is the direct fix
        // for the Glimpse bug where clips 2+ had no audio.
        try verifyAudioConnection(on: output)

        let url = makeTemporaryURL()

        return try await withCheckedThrowingContinuation { continuation in
            recordingContinuation = continuation
            output.startRecording(to: url, recordingDelegate: self)
            Task { @MainActor in self.isRecording = true }
        }
    }

    /// Stops the current recording and waits for the file to be finalised.
    func stopRecording() {
        movieOutput?.stopRecording()
    }

    // MARK: - Camera switching

    func switchCamera() async throws {
        guard let s = session else { return }
        let newPosition: CameraPosition = cameraPosition == .back ? .front : .back
        let newInput = try makeVideoInput(position: newPosition)

        s.beginConfiguration()
        if let old = videoDeviceInput { s.removeInput(old) }
        guard s.canAddInput(newInput) else {
            s.commitConfiguration()
            throw CameraError.deviceNotFound
        }
        s.addInput(newInput)
        s.commitConfiguration()

        videoDeviceInput = newInput
        cameraPosition = newPosition
    }

    // MARK: - Zoom / focus / torch

    func setZoom(_ factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }
        try? device.lockForConfiguration()
        device.videoZoomFactor = max(1, min(factor, device.activeFormat.videoMaxZoomFactor))
        device.unlockForConfiguration()
    }

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

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord,
                                     mode: .videoRecording,
                                     options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
        try audioSession.setActive(true)
    }

    private func makeVideoInput(position: CameraPosition) throws -> AVCaptureDeviceInput {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: position.avPosition) else {
            throw CameraError.deviceNotFound
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            throw CameraError.sessionSetupFailed
        }
        return input
    }

    private func makeAudioInput() throws -> AVCaptureDeviceInput {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw CameraError.audioDeviceNotFound
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            throw CameraError.audioDeviceNotFound
        }
        return input
    }

    private func verifyAudioConnection(on output: AVCaptureMovieFileOutput) throws {
        guard let connection = output.connection(with: .audio) else {
            throw CameraError.audioConnectionMissing
        }
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

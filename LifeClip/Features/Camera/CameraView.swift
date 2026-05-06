import SwiftUI
import AVFoundation

/// Full-screen camera interface for recording a single clip.
/// Dismisses itself and calls onSave(url, duration) when recording is finished.
struct CameraView: View {
    var onSave: (URL, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraService()

    // Recording state
    @State private var recordingStart: Date?
    @State private var elapsed: Double = 0
    @State private var timer: Timer?

    // Clip duration limit (seconds). Users can choose 3 / 5 / 10.
    @State private var durationLimit: Double = 5

    // UI feedback
    @State private var focusPoint: CGPoint?
    @State private var showFocusRing = false
    @State private var zoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var torchOn = false
    @State private var setupError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let session = camera.session {
                CameraPreviewView(session: session)
                    .ignoresSafeArea()
                    .gesture(tapToFocusGesture)
                    .gesture(pinchToZoomGesture)
            }

            // Focus ring
            if showFocusRing, let pt = focusPoint {
                FocusRingView()
                    .position(pt)
            }

            // Error banner
            if let err = setupError ?? camera.cameraError?.localizedDescription {
                errorBanner(err)
            }

            // HUD overlay
            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .task { await setupCamera() }
        .onDisappear { teardown() }
        .onChange(of: camera.lastRecordedURL) { _, url in
            guard let url else { return }
            finishRecording(url: url)
        }
        .statusBarHidden(true)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.4), in: Circle())
            }

            Spacer()

            // Elapsed / limit indicator
            if camera.isRecording {
                Text(String(format: "%.1f / %.0fs", elapsed, durationLimit))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.red.opacity(0.8), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            // Torch
            Button {
                torchOn.toggle()
                camera.setTorch(torchOn)
            } label: {
                Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                    .font(.title3.bold())
                    .foregroundStyle(torchOn ? .yellow : .white)
                    .padding(12)
                    .background(.black.opacity(0.4), in: Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .animation(.easeInOut(duration: 0.2), value: camera.isRecording)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 24) {
            // Duration picker
            if !camera.isRecording {
                durationPicker
                    .transition(.opacity)
            }

            HStack(spacing: 48) {
                // Flip camera
                Button {
                    Task { try? await camera.switchCamera() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .disabled(camera.isRecording)

                // Record button
                RecordButton(isRecording: camera.isRecording) {
                    Task { await handleRecordTap() }
                }

                // Placeholder spacer (mirrors flip button)
                Color.clear
                    .frame(width: 52, height: 52)
            }
        }
        .padding(.bottom, 48)
        .animation(.easeInOut(duration: 0.2), value: camera.isRecording)
    }

    private var durationPicker: some View {
        HStack(spacing: 0) {
            ForEach([3.0, 5.0, 10.0], id: \.self) { d in
                Button {
                    durationLimit = d
                } label: {
                    Text("\(Int(d))s")
                        .font(.subheadline.bold())
                        .foregroundStyle(durationLimit == d ? .black : .white)
                        .frame(width: 52, height: 32)
                        .background(durationLimit == d ? .white : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(4)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Gestures

    private var tapToFocusGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let size = UIScreen.main.bounds.size
                // Normalise to [0,1] for AVFoundation, then store screen-space for the ring
                let normPt = CGPoint(x: value.location.x / size.width,
                                     y: value.location.y / size.height)
                camera.focusAt(normPt)
                focusPoint = value.location
                showFocusRing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    showFocusRing = false
                }
            }
    }

    private var pinchToZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let newZoom = lastZoom * scale
                zoom = max(1.0, min(newZoom, 5.0))
                camera.setZoom(zoom)
            }
            .onEnded { _ in lastZoom = zoom }
    }

    // MARK: - Actions

    private func setupCamera() async {
        do {
            try await camera.startSession()
        } catch {
            setupError = error.localizedDescription
        }
    }

    private func teardown() {
        stopTimer()
        camera.stopSession()
    }

    private func handleRecordTap() async {
        if camera.isRecording {
            camera.stopRecording()
            stopTimer()
        } else {
            do {
                startTimer()
                _ = try await camera.startRecording()
            } catch {
                stopTimer()
                setupError = error.localizedDescription
            }
        }
    }

    private func finishRecording(url: URL) {
        stopTimer()
        let duration = elapsed > 0 ? elapsed : durationLimit
        onSave(url, duration)
        dismiss()
    }

    // MARK: - Timer

    private func startTimer() {
        elapsed = 0
        recordingStart = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let start = recordingStart else { return }
            elapsed = Date().timeIntervalSince(start)
            if elapsed >= durationLimit {
                camera.stopRecording()
                stopTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        VStack {
            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(12)
                .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                .padding()
            Spacer()
        }
    }
}

// MARK: - RecordButton

private struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 72, height: 72)

                RoundedRectangle(cornerRadius: isRecording ? 8 : 36)
                    .fill(.red)
                    .frame(width: isRecording ? 30 : 58, height: isRecording ? 30 : 58)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
            }
        }
    }
}

// MARK: - FocusRingView

private struct FocusRingView: View {
    @State private var scale: CGFloat = 1.4
    @State private var opacity: Double = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(.yellow, lineWidth: 1.5)
            .frame(width: 70, height: 70)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { scale = 1.0 }
                withAnimation(.easeIn(duration: 0.4).delay(0.8)) { opacity = 0.0 }
            }
    }
}

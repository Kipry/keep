import SwiftUI
import AVFoundation

struct CameraView: View {
    var onSave: (URL, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraService()

    // Recording
    @State private var recordingStart: Date?
    @State private var elapsed: Double = 0
    @State private var timer: Timer?
    @State private var durationLimit: Double = 1  // default 1 second

    // UI
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

            if showFocusRing, let pt = focusPoint {
                FocusRingView().position(pt)
            }

            if let err = setupError ?? camera.cameraError?.localizedDescription {
                errorBanner(err)
            }

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
            .disabled(camera.cameraPosition == .front)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .animation(.easeInOut(duration: 0.2), value: camera.isRecording)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 20) {
            if !camera.isRecording {
                durationPicker.transition(.opacity)
            }

            // Lens picker — only shown for back camera with multiple lenses
            if camera.availableLenses.count > 1 && !camera.isRecording {
                lensPicker.transition(.opacity)
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

                RecordButton(isRecording: camera.isRecording) {
                    Task { await handleRecordTap() }
                }

                Color.clear.frame(width: 52, height: 52)
            }
        }
        .padding(.bottom, 48)
        .animation(.easeInOut(duration: 0.2), value: camera.isRecording)
    }

    // MARK: - Duration picker

    private var durationPicker: some View {
        HStack(spacing: 0) {
            ForEach([1.0, 3.0, 5.0], id: \.self) { d in
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

    // MARK: - Lens picker

    private var lensPicker: some View {
        HStack(spacing: 4) {
            ForEach(camera.availableLenses) { lens in
                Button {
                    Task { try? await camera.switchLens(to: lens) }
                } label: {
                    Text(lens.rawValue)
                        .font(.caption.bold())
                        .foregroundStyle(camera.currentLens == lens ? .black : .white)
                        .frame(width: 46, height: 32)
                        .background(
                            camera.currentLens == lens
                                ? Color.white
                                : Color.black.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        // Active lens gets a subtle golden ring like the native Camera app
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(camera.currentLens == lens ? Color.yellow.opacity(0.6) : .clear,
                                        lineWidth: 1)
                        )
                }
                .disabled(camera.isRecording)
            }
        }
        .padding(4)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Gestures

    private var tapToFocusGesture: some Gesture {
        SpatialTapGesture().onEnded { value in
            let size = UIScreen.main.bounds.size
            let normPt = CGPoint(x: value.location.x / size.width,
                                 y: value.location.y / size.height)
            camera.focusAt(normPt)
            focusPoint = value.location
            showFocusRing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showFocusRing = false }
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
        do { try await camera.startSession() }
        catch { setupError = error.localizedDescription }
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
        onSave(url, elapsed > 0 ? elapsed : durationLimit)
        dismiss()
    }

    // MARK: - Timer

    private func startTimer() {
        elapsed = 0
        recordingStart = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let start = recordingStart else { return }
            elapsed = Date().timeIntervalSince(start)
            if elapsed >= durationLimit {
                camera.stopRecording()
                stopTimer()
            }
        }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

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
                // Pulse ring while recording
                if isRecording {
                    Circle()
                        .stroke(.red.opacity(0.3), lineWidth: 6)
                        .frame(width: 84, height: 84)
                        .scaleEffect(isRecording ? 1.15 : 1)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                   value: isRecording)
                }
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

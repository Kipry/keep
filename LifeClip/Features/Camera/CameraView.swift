import SwiftUI
import AVFoundation

struct CameraView: View {
    var onSave: (URL, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraService()

    @State private var recordingStart: Date?
    @State private var elapsed: Double = 0
    @State private var timer: Timer?
    @State private var durationLimit: Double = 1

    @State private var focusPoint: CGPoint?
    @State private var showFocusRing = false
    @State private var lastZoom: CGFloat = 1.0
    @State private var showZoomLabel = false
    @State private var zoomLabelTask: Task<Void, Never>?
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

            if showZoomLabel {
                Text(String(format: "%.1f×", camera.displayZoomFactor))
                    .font(.mono(15, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.55), in: Capsule())
                    .transition(.opacity)
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
        .animation(.easeInOut(duration: 0.25), value: showZoomLabel)
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
                HStack(spacing: 7) {
                    Circle()
                        .fill(Theme.amber)
                        .frame(width: 8, height: 8)
                    Text(String(format: "%.1fs", elapsed))
                        .font(.mono(13, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.55), in: Capsule())
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            Button {
                torchOn.toggle()
                camera.setTorch(torchOn)
            } label: {
                Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                    .font(.title3.bold())
                    .foregroundStyle(torchOn ? Theme.amber : .white)
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

            HStack {
                Color.clear.frame(width: 52, height: 52)

                Spacer()

                RecordButton(
                    isRecording: camera.isRecording,
                    progress: durationLimit > 0
                        ? CGFloat(min(elapsed / durationLimit, 1.0))
                        : 0
                ) {
                    Task { await handleRecordTap() }
                }

                Spacer()

                Button {
                    Task { try? await camera.switchCamera() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .disabled(camera.isRecording)
            }
            .padding(.horizontal, 36)
        }
        .padding(.bottom, 48)
        .animation(.easeInOut(duration: 0.2), value: camera.isRecording)
    }

    // MARK: - Duration picker

    private var durationPicker: some View {
        HStack(spacing: 6) {
            ForEach([1.0, 3.0, 5.0], id: \.self) { d in
                Button {
                    durationLimit = d
                } label: {
                    Text("\(Int(d))s")
                        .font(.mono(13, weight: .medium))
                        .foregroundStyle(durationLimit == d ? Theme.ink : .white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            durationLimit == d ? .white : Color.black.opacity(0.35),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(durationLimit == d ? .clear : .white.opacity(0.4), lineWidth: 1)
                        )
                }
            }
        }
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
                camera.setZoom(lastZoom * scale)
                showZoomLabel = true
                zoomLabelTask?.cancel()
            }
            .onEnded { _ in
                lastZoom = camera.currentZoomFactor
                zoomLabelTask = Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if !Task.isCancelled {
                        withAnimation { showZoomLabel = false }
                    }
                }
            }
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
    let progress: CGFloat   // 0.0 – 1.0, drives the amber ring
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Amber progress arc, sits just outside the white ring — replaces the dashed guide circle
                if isRecording {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Theme.amber,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 82, height: 82)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.06), value: progress)
                        .shadow(color: Theme.amber.opacity(0.6), radius: 4)
                }

                // White border ring
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 72, height: 72)

                // Inner fill: circle → rounded square when recording
                RoundedRectangle(cornerRadius: isRecording ? 8 : 36)
                    .fill(isRecording ? Theme.amber : .red)
                    .frame(
                        width:  isRecording ? 28 : 56,
                        height: isRecording ? 28 : 56
                    )
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

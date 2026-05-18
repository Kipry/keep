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
    @State private var isHoldRecording = false
    @State private var holdStartTask: Task<Void, Never>?
    @State private var holdZoomStart: CGFloat = 1.0
    @State private var pendingCameraFlip = false

    private let holdThreshold: TimeInterval = 0.25

    @State private var focusPoint: CGPoint?
    @State private var showFocusRing = false
    @State private var lastZoom: CGFloat = 1.0
    @State private var showZoomLabel = false
    @State private var zoomLabelTask: Task<Void, Never>?
    @State private var torchOn = false
    @State private var screenFlashOn = false
    @State private var savedBrightness: CGFloat = UIScreen.main.brightness
    @State private var setupError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let session = camera.session {
                CameraPreviewView(session: session)
                    .ignoresSafeArea()
                    .highPriorityGesture(doubleTapToFlipGesture)
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

            // Screen flash: bright white fill-light for front camera.
            // Sits below the controls so buttons remain visible and tappable.
            if screenFlashOn {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
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
                if camera.cameraPosition == .front {
                    torchOn ? activateScreenFlash() : deactivateScreenFlash()
                } else {
                    camera.setTorch(torchOn)
                }
            } label: {
                Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                    .font(.title3.bold())
                    .foregroundStyle(torchOn ? Theme.amber : .white)
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
        VStack(spacing: 20) {
            if !camera.isRecording {
                durationPicker.transition(.opacity)
            }

            HStack {
                Color.clear.frame(width: 52, height: 52)

                Spacer()

                RecordButton(
                    isRecording: camera.isRecording,
                    progress: isHoldRecording ? 0
                        : (durationLimit > 0 ? CGFloat(min(elapsed / durationLimit, 1.0)) : 0),
                    onPressDown: { handlePressDown() },
                    onRelease:   { handleRelease() },
                    onDrag:      { handleDrag($0) }
                )

                Spacer()

                Button { handleCameraFlip() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.black.opacity(0.4), in: Circle())
                }
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

    private var doubleTapToFlipGesture: some Gesture {
        TapGesture(count: 2).onEnded { handleCameraFlip() }
    }

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

    private func handleCameraFlip() {
        if screenFlashOn { torchOn = false; deactivateScreenFlash() }
        if camera.isRecording {
            // AVCaptureMovieFileOutput cannot switch inputs mid-recording.
            // Stop the current clip, set a flag, then finishRecording() will
            // flip and restart automatically.
            pendingCameraFlip = true
            camera.stopRecording()
            stopTimer()
        } else {
            Task {
                try? await camera.switchCamera()
                if isHoldRecording { holdZoomStart = camera.currentZoomFactor }
            }
        }
    }

    private func setupCamera() async {
        do { try await camera.startSession() }
        catch { setupError = error.localizedDescription }
    }

    private func teardown() {
        stopTimer()
        if screenFlashOn { deactivateScreenFlash() }
        camera.stopSession()
    }

    // Called on every finger-down on the shutter button.
    // Schedules a hold-mode start after the threshold; quick releases cancel it.
    private func handlePressDown() {
        guard holdStartTask == nil, !camera.isRecording else { return }
        holdStartTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(holdThreshold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            holdZoomStart = camera.currentZoomFactor  // snapshot zoom at hold start
            isHoldRecording = true
            startTimer()
            do { _ = try await camera.startRecording() }
            catch { isHoldRecording = false; stopTimer(); setupError = error.localizedDescription }
        }
    }

    // Called on finger-up. Decides tap vs. hold based on whether hold mode activated.
    private func handleRelease() {
        if let task = holdStartTask {
            task.cancel()
            holdStartTask = nil
            if isHoldRecording {
                isHoldRecording = false
                camera.stopRecording()
                stopTimer()
                lastZoom = camera.currentZoomFactor
                zoomLabelTask?.cancel()
                zoomLabelTask = Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if !Task.isCancelled { withAnimation { showZoomLabel = false } }
                }
            } else {
                Task { await handleRecordTap() }
            }
        } else if camera.isRecording {
            Task { await handleRecordTap() }
        }
    }

    // Called while finger is held and dragged. Only active in hold-recording mode.
    // Dragging up (negative y translation) zooms in; dragging down zooms out.
    private func handleDrag(_ verticalTranslation: CGFloat) {
        guard isHoldRecording else { return }
        let newZoom = holdZoomStart - verticalTranslation * 0.013
        camera.setZoom(newZoom)
        zoomLabelTask?.cancel()
        showZoomLabel = true
    }

    private func activateScreenFlash() {
        savedBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 1.0
        withAnimation(.easeIn(duration: 0.1)) { screenFlashOn = true }
    }

    private func deactivateScreenFlash() {
        UIScreen.main.brightness = savedBrightness
        withAnimation(.easeOut(duration: 0.2)) { screenFlashOn = false }
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
        guard pendingCameraFlip else { dismiss(); return }
        // A camera flip was requested mid-recording: switch camera now, then
        // restart recording automatically if the user is still holding.
        pendingCameraFlip = false
        Task {
            try? await camera.switchCamera()
            holdZoomStart = camera.currentZoomFactor
            guard isHoldRecording else { return }
            startTimer()
            do { _ = try await camera.startRecording() }
            catch { isHoldRecording = false; setupError = error.localizedDescription; dismiss() }
        }
    }

    // MARK: - Timer

    private func startTimer() {
        elapsed = 0
        recordingStart = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let start = recordingStart else { return }
            elapsed = Date().timeIntervalSince(start)
            if !isHoldRecording && elapsed >= durationLimit {
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
    let onPressDown: () -> Void
    let onRelease: () -> Void
    let onDrag: (CGFloat) -> Void   // vertical translation (negative = up = zoom in)

    @State private var isPressing = false

    var body: some View {
        ZStack {
            // Amber progress arc, sits just outside the white ring
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
        .contentShape(Circle().size(CGSize(width: 82, height: 82)))
        .scaleEffect(isPressing ? 0.94 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressing)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isPressing {
                        isPressing = true
                        onPressDown()
                    } else {
                        onDrag(value.translation.height)
                    }
                }
                .onEnded { _ in
                    isPressing = false
                    onRelease()
                }
        )
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

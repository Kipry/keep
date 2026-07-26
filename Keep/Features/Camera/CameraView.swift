import SwiftUI
import AVFoundation
import AVKit
import UIKit

struct CameraView: View {
    var onSave: (URL, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CameraService()

    @AppStorage("defaultRecordingDuration") private var defaultDuration: Double = 1.0

    @State private var recordingStart: Date?
    @State private var elapsed: Double = 0
    @State private var timer: Timer?
    @State private var durationLimit: Double = 1.0
    @State private var isHoldRecording = false
    @State private var holdStartTask: Task<Void, Never>?
    @State private var holdZoomStart: CGFloat = 1.0
    @State private var pendingCameraFlip = false
    // Hands-free lock (Snapchat-style): slide left toward the lock icon while
    // hold-recording to keep recording after lifting the finger.
    @State private var isLocked = false
    @State private var lockArmed = false

    // Horizontal travel (pts) toward the lock icon that engages the lock.
    private let lockSlideThreshold: CGFloat = 80

    private let holdThreshold: TimeInterval = 0.25

    @State private var focusPoint: CGPoint?
    @State private var showFocusRing = false
    @State private var lastZoom: CGFloat = 1.0
    @State private var showZoomLabel = false
    @State private var zoomLabelTask: Task<Void, Never>?
    @State private var showExposureControl = false
    @State private var exposureHideTask: Task<Void, Never>?
    @State private var dragStartBias: Float = 0
    @State private var torchOn = false
    @State private var screenFlashOn = false
    @State private var savedBrightness: CGFloat = UIScreen.main.brightness
    @State private var setupError: String?
    @State private var deniedPermission: CameraError?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let denied = deniedPermission {
                permissionDeniedView(denied)
            } else {
                cameraUI
            }
        }
        .task {
            durationLimit = defaultDuration
            // Warm up a one-shot location fix (and show the opt-in prompt on
            // first use) so it's ready by the time the clip is saved.
            LocationService.shared.prime()
            await setupCamera()
        }
        .onDisappear { teardown() }
        .onChange(of: scenePhase) { _, phase in
            // Returning from Settings after granting access: retry setup so the
            // user isn't stranded on the permission screen.
            if phase == .active, deniedPermission != nil {
                deniedPermission = nil
                Task { await setupCamera() }
            }
        }
        .onChange(of: camera.lastRecordedURL) { _, url in
            guard let url else { return }
            finishRecording(url: url)
        }
        // Strong, tactile haptics the moment recording actually starts/stops —
        // hooked to camera.isRecording so every trigger path (tap, hold, lock,
        // auto-stop, volume button) gets the same physical feedback.
        .onChange(of: camera.isRecording) { _, recording in
            recordingHaptic(started: recording)
        }
        .statusBarHidden(true)
        .animation(.easeInOut(duration: 0.25), value: showZoomLabel)
        .animation(.easeInOut(duration: 0.2), value: showExposureControl)
    }

    // MARK: - Camera UI

    private var cameraUI: some View {
        ZStack {
            // Volume buttons act as a shutter (Apple's sanctioned capture-event
            // API): press once to start recording, press again to stop.
            if #available(iOS 17.2, *) {
                VolumeShutterBridge {
                    Task { await handleRecordTap() }
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }

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

            if showExposureControl, let pt = focusPoint {
                let sw = UIScreen.main.bounds.width
                let sh = UIScreen.main.bounds.height
                ExposureSliderView(
                    bias: camera.exposureBias,
                    onDragStart: { dragStartBias = camera.exposureBias },
                    onDragChanged: { translation in
                        let newBias = dragStartBias + Float(-translation) * (3.5 / 104)
                        camera.setExposureBias(newBias)
                        scheduleHideExposureControl()
                    }
                )
                .position(
                    x: min(pt.x + 62, sw - 26),
                    y: max(min(pt.y, sh - 90), 90)
                )
                .transition(.opacity)
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

            // Screen flash: bright white border fill-light for front camera.
            // Edge gradients glow white while keeping the camera preview
            // visible in the centre — the same technique Snapchat uses.
            if screenFlashOn {
                GeometryReader { geo in
                    ZStack {
                        LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: geo.size.height * 0.4)
                            .frame(maxHeight: .infinity, alignment: .top)
                        LinearGradient(colors: [.white, .clear], startPoint: .bottom, endPoint: .top)
                            .frame(height: geo.size.height * 0.4)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.28)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        LinearGradient(colors: [.white, .clear], startPoint: .trailing, endPoint: .leading)
                            .frame(width: geo.size.width * 0.28)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }

            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
    }

    // MARK: - Permission denied

    private func permissionDeniedView(_ error: CameraError) -> some View {
        let isCamera: Bool = { if case .permissionDenied = error { return true } else { return false } }()
        let title: LocalizedStringKey = isCamera ? "Camera Access Needed" : "Microphone Access Needed"
        let message: LocalizedStringKey = isCamera
            ? "keep. needs camera access to record your daily moments. Turn it on in Settings to continue."
            : "keep. needs microphone access to capture sound with your clips. Turn it on in Settings to continue."
        return VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.4), in: Circle())
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            VStack(spacing: 16) {
                Image(systemName: isCamera ? "video.slash.fill" : "mic.slash.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.amber)

                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 32)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("Open Settings")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white, in: Capsule())
                }
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }

            Spacer()
            Spacer()
        }
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
        VStack(spacing: 16) {
            if !camera.isRecording {
                durationPicker.transition(.opacity)
            }

            // Hands-free lock cue (only while hold-recording).
            if isLocked {
                lockHint("lock.fill", "Tap the shutter to stop")
            } else if isHoldRecording {
                lockHint("arrow.left", "Slide to lock")
            }

            HStack {
                lockSlot

                Spacer()

                RecordButton(
                    isRecording: camera.isRecording,
                    progress: (isHoldRecording || isLocked) ? 0
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
        .animation(.easeInOut(duration: 0.2), value: isHoldRecording)
        .animation(.easeInOut(duration: 0.2), value: isLocked)
    }

    // Left-hand slot doubling as the slide-to-lock target during hold-recording.
    private var lockSlot: some View {
        ZStack {
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 48, height: 48)
                    .background(Theme.amber, in: Circle())
                    .shadow(color: Theme.amber.opacity(0.5), radius: 8)
            } else if isHoldRecording {
                Image(systemName: "lock.open")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.45), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
            } else {
                Color.clear
            }
        }
        .frame(width: 52, height: 52)
    }

    private func lockHint(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold))
            Text(text).font(.mono(12, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.5), in: Capsule())
        .transition(.opacity)
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
            withAnimation { showExposureControl = true }
            scheduleHideExposureControl()
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
        showExposureControl = false
        exposureHideTask?.cancel()
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
        catch let error as CameraError where error.isPermissionDenial {
            deniedPermission = error
        }
        catch { setupError = error.localizedDescription }
    }

    private func teardown() {
        stopTimer()
        exposureHideTask?.cancel()
        if screenFlashOn { deactivateScreenFlash() }
        camera.setExposureBias(0)
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
        // The slide-to-lock gesture just engaged: keep recording hands-free and
        // ignore the finger lift entirely.
        if lockArmed {
            lockArmed = false
            holdStartTask = nil
            return
        }
        // A subsequent tap while locked stops the hands-free recording.
        if isLocked {
            isLocked = false
            isHoldRecording = false
            camera.stopRecording()
            stopTimer()
            return
        }
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
    // Sliding left toward the lock icon locks the recording hands-free; otherwise
    // dragging up (negative y translation) zooms in and dragging down zooms out.
    private func handleDrag(_ translation: CGSize) {
        guard isHoldRecording, !isLocked else { return }
        // Slide left toward the lock icon → lock hands-free recording.
        if translation.width < -lockSlideThreshold && abs(translation.width) > abs(translation.height) {
            engageLock()
            return
        }
        let newZoom = holdZoomStart - translation.height * 0.013
        camera.setZoom(newZoom)
        zoomLabelTask?.cancel()
        showZoomLabel = true
    }

    private func engageLock() {
        isLocked = true
        lockArmed = true
        withAnimation { showZoomLabel = false }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func scheduleHideExposureControl() {
        exposureHideTask?.cancel()
        exposureHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { showExposureControl = false }
        }
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

    // Heavy single thump when recording starts; a sharp rigid double-tick when
    // it stops — unmistakably physical, like a mechanical shutter engaging.
    private func recordingHaptic(started: Bool) {
        if started {
            let gen = UIImpactFeedbackGenerator(style: .heavy)
            gen.prepare()
            gen.impactOccurred(intensity: 1.0)
        } else {
            let gen = UIImpactFeedbackGenerator(style: .rigid)
            gen.prepare()
            gen.impactOccurred(intensity: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                gen.impactOccurred(intensity: 0.7)
            }
        }
    }

    private func finishRecording(url: URL) {
        stopTimer()
        onSave(url, elapsed > 0 ? elapsed : durationLimit)
        guard pendingCameraFlip else {
            isLocked = false
            lockArmed = false
            dismiss()
            return
        }
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
            // The timer is scheduled on the main run loop, so this body always
            // runs on the main actor — the compiler just can't see that through
            // the nonisolated closure. Asserting it keeps the call synchronous;
            // hopping via Task would delay the stop past the duration limit.
            MainActor.assumeIsolated {
                guard let start = recordingStart else { return }
                elapsed = Date().timeIntervalSince(start)
                if !isHoldRecording && elapsed >= durationLimit {
                    camera.stopRecording()
                    stopTimer()
                }
            }
        }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    /// Dismissible. `setupError` was write-only, so once any camera error fired
    /// the banner covered the top of the viewfinder for the rest of the session
    /// with no way to clear it.
    private func errorBanner(_ message: String) -> some View {
        VStack {
            HStack(alignment: .top, spacing: 10) {
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { setupError = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(12)
            .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            .padding()
            Spacer()
        }
    }
}

// MARK: - VolumeShutterBridge

/// Bridges the hardware volume buttons to the record action via
/// AVCaptureEventInteraction — the system API for camera hardware triggers.
/// Only fires while a capture session is active, so it can't hijack the
/// volume buttons anywhere else in the app.
@available(iOS 17.2, *)
private struct VolumeShutterBridge: UIViewRepresentable {
    let onPress: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPress: onPress) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let coordinator = context.coordinator
        let interaction = AVCaptureEventInteraction { event in
            guard event.phase == .began else { return }
            coordinator.onPress()
        }
        interaction.isEnabled = true
        view.addInteraction(interaction)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onPress = onPress
    }

    final class Coordinator {
        var onPress: () -> Void
        init(onPress: @escaping () -> Void) { self.onPress = onPress }
    }
}

// MARK: - RecordButton

private struct RecordButton: View {
    let isRecording: Bool
    let progress: CGFloat   // 0.0 – 1.0, drives the amber ring
    let onPressDown: () -> Void
    let onRelease: () -> Void
    let onDrag: (CGSize) -> Void   // full translation (up = zoom in, left = lock)

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
                        onDrag(value.translation)
                    }
                }
                .onEnded { _ in
                    isPressing = false
                    onRelease()
                }
        )
    }
}

// MARK: - ExposureSliderView

private struct ExposureSliderView: View {
    let bias: Float
    let onDragStart: () -> Void
    let onDragChanged: (CGFloat) -> Void

    private let trackH: CGFloat = 104
    private let halfH:  CGFloat = 52
    private let displayRange: Float = 3.5

    @State private var isDragging = false

    /// –1 = full bottom (underexposed), 0 = centre, +1 = full top (overexposed)
    private var norm: CGFloat {
        CGFloat(max(-1, min(1, bias / displayRange)))
    }

    var body: some View {
        ZStack {
            // Track background
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.white.opacity(0.22))
                .frame(width: 2.5, height: trackH)

            // Amber fill from centre to sun position
            if abs(norm) > 0.02 {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.amber.opacity(0.9))
                    .frame(width: 2.5, height: abs(norm) * halfH)
                    .offset(y: norm > 0 ? -(abs(norm) * halfH / 2)
                                        :  (abs(norm) * halfH / 2))
            }

            // Sun handle — moves up for positive bias, down for negative
            Image(systemName: "sun.max.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.amber)
                .shadow(color: Theme.amber.opacity(0.55), radius: 4)
                .offset(y: -norm * halfH)
        }
        .frame(width: 28, height: trackH)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.black.opacity(0.42), in: Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging { isDragging = true; onDragStart() }
                    onDragChanged(value.translation.height)
                }
                .onEnded { _ in isDragging = false }
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

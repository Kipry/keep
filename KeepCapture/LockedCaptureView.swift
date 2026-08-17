// AppIntents: `KeepCaptureIntent.appContext` is declared on the
// `CameraCaptureIntent` protocol, and this project enables
// MEMBER_IMPORT_VISIBILITY — so the module defining a member has to be
// imported explicitly, even though the intent type itself is in this module.
// AVKit, not AVFoundation: AVCaptureEventInteraction lives there (same as the
// in-app CameraView's volume-button bridge).
import AppIntents
import AVFoundation
import AVKit
import LockedCameraCapture
import SwiftUI
import UIKit

// MARK: - Locked capture UI

/// The whole locked-camera experience: viewfinder, shutter, one confirmation.
///
/// Everything here that touches the *camera* is the same as inside the app,
/// and deliberately so — the shutter, the duration pills, the exposure slider
/// and the focus ring are literally the same views (`CameraControls.swift`),
/// driven by the same `CameraService`. None of that needs the user's data, so
/// none of it is blocked by the locked sandbox. An earlier version of this
/// screen cut all of it on the assumption that a locked capture should be
/// minimal; the assumption was wrong, and someone recording a one-second clip
/// at arm's length needs the exposure control *more* than they do in the app,
/// not less.
///
/// What genuinely can't cross the boundary is data: the project list, and any
/// preference written back. So a duration picked here applies to this clip and
/// is forgotten, and the destination is whatever the app last told us through
/// the intent's app context.
///
/// Fonts are system fonts on purpose: the app registers JetBrains Mono at
/// launch, and that registration has not happened in this process, so the
/// branded faces would silently fall back anyway. Colours come from `Theme`,
/// which is pure values and compiles in here cleanly.
struct LockedCaptureView: View {
    let session: LockedCameraCaptureSession

    @StateObject private var camera = CameraService()

    /// Display/behaviour hints handed over by the app through the intent's
    /// app context — the only channel that crosses this sandbox boundary.
    @State private var context = KeepCaptureContext.fallback

    private let startHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let stopHaptic  = UIImpactFeedbackGenerator(style: .rigid)

    @State private var recordingStart: Date?
    @State private var elapsed: Double = 0
    @State private var timer: Timer?
    @State private var durationLimit = RecordingDuration.standard
    @State private var isHoldRecording = false
    @State private var holdStartTask: Task<Void, Never>?
    @State private var holdZoomStart: CGFloat = 1.0
    @State private var pendingCameraFlip = false
    @State private var isLocked = false
    @State private var lockArmed = false

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

    @State private var didCapture = false
    @State private var isOpeningApp = false

    var body: some View {
        // GeometryReader rather than `UIScreen.main.bounds`: this scene is the
        // system's to size, not ours, and the focus point has to be normalised
        // against the view that was actually tapped.
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let avSession = camera.session {
                    CameraPreviewView(session: avSession)
                        .ignoresSafeArea()
                        .gesture(tapToFocusGesture(in: geo.size))
                        .gesture(pinchToZoomGesture)
                }

                if showFocusRing, let pt = focusPoint {
                    FocusRingView().position(pt)
                }

                if showExposureControl, let pt = focusPoint {
                    ExposureSliderView(
                        bias: camera.exposureBias,
                        onDragStart: { dragStartBias = camera.exposureBias },
                        onDragChanged: { translation in
                            camera.setExposureBias(dragStartBias + Float(-translation) * (3.5 / 104))
                            scheduleHideExposureControl()
                        }
                    )
                    .position(
                        x: min(pt.x + 62, geo.size.width - 26),
                        y: max(min(pt.y, geo.size.height - 90), 90)
                    )
                    .transition(.opacity)
                }

                if showZoomLabel {
                    Text(String(format: "%.1f×", camera.displayZoomFactor))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.55), in: Capsule())
                        .transition(.opacity)
                }

                // Screen flash: bright white border fill-light for the front
                // camera, which has no torch. Edge gradients glow while the
                // preview stays visible in the centre.
                if screenFlashOn {
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
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }

                if didCapture {
                    savedOverlay
                } else {
                    VStack {
                        topBar.padding(.top, 14)
                        Spacer()
                        bottomBar
                    }
                }

                if let error = camera.cameraError?.localizedDescription {
                    Text(verbatim: error)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(14)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 28)
                }
            }
        }
        // Keeps the hardware capture button (and Camera Control) working — and,
        // just as importantly, tells the system this extension is an active
        // camera experience. Without an AVCaptureEventInteraction the system
        // suspends a locked capture extension after a few idle seconds.
        .background(CaptureEventCatcher { handleRecordTap() })
        .task {
            // Session content, not Documents: this extension's own container is
            // wiped on suspension, so anything written there would be gone
            // before the app could ever import it.
            camera.outputDirectory = session.sessionContentURL
            if let handed = try? await KeepCaptureIntent.appContext {
                context = handed
            }
            // Starts on the length the user chose in the app, and can be
            // changed from here for this clip only.
            durationLimit = RecordingDuration.resolve(context.duration)
            startHaptic.prepare()
            try? await camera.startSession()
        }
        .onDisappear {
            holdStartTask?.cancel()
            zoomLabelTask?.cancel()
            exposureHideTask?.cancel()
            stopTimer()
            if screenFlashOn { deactivateScreenFlash() }
            camera.setTorch(false)
            camera.setExposureBias(0)
            camera.stopSession()
        }
        .onChange(of: camera.lastRecordedURL) { _, url in
            guard url != nil else { return }
            finishRecording()
        }
        .onChange(of: camera.isRecording) { _, recording in
            guard recording else { return }
            startHaptic.impactOccurred(intensity: 1.0)
            stopHaptic.prepare()
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: showZoomLabel)
        .animation(.easeInOut(duration: 0.2), value: showExposureControl)
    }

    // MARK: Top bar

    private var topBar: some View {
        // The leading spacer is the torch button's twin, so the chip stays
        // optically centred rather than pushed left by the button's width.
        HStack(alignment: .top, spacing: 8) {
            Color.clear.frame(width: 43, height: 43)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                destinationChip
                if camera.isRecording {
                    HStack(spacing: 7) {
                        Circle().fill(Theme.amber).frame(width: 8, height: 8)
                        Text(String(format: "%.1fs", elapsed))
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
                }
            }

            Spacer(minLength: 0)

            Button {
                torchOn.toggle()
                if camera.cameraPosition == .front {
                    torchOn ? activateScreenFlash() : deactivateScreenFlash()
                } else {
                    camera.setTorch(torchOn)
                }
            } label: {
                Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(torchOn ? Theme.amber : .white)
                    .frame(width: 43, height: 43)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Light")
            .accessibilityValue(torchOn ? "On" : "Off")
        }
        .padding(.horizontal, 20)
        .animation(.easeInOut(duration: 0.2), value: camera.isRecording)
    }

    /// Names the project the clip is headed for, when the app has told us one.
    /// Says so plainly when it hasn't, rather than inventing a destination —
    /// this sandbox genuinely cannot read the project list, and the honest
    /// version ("filed when you unlock") is also the true one.
    private var destinationChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 11, weight: .semibold))
            Text(context.projectName.map { "\($0)" } ?? String(localized: "Filed when you unlock"))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.45), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            if !camera.isRecording {
                DurationPicker(selection: $durationLimit).transition(.opacity)
            }

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
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(camera.isRecording ? "Stop recording" : "Record")
                .accessibilityAction { handleRecordTap() }

                Spacer()

                Button { handleCameraFlip() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Switch camera")
            }
            .padding(.horizontal, 36)
        }
        .padding(.bottom, 44)
        .animation(.easeInOut(duration: 0.2), value: camera.isRecording)
        .animation(.easeInOut(duration: 0.2), value: isHoldRecording)
        .animation(.easeInOut(duration: 0.2), value: isLocked)
    }

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
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.5), in: Capsule())
        .transition(.opacity)
    }

    // MARK: Gestures

    private func tapToFocusGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            guard !didCapture else { return }
            camera.focusAt(CGPoint(x: value.location.x / size.width,
                                   y: value.location.y / size.height))
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
                hideZoomLabelSoon()
            }
    }

    private func hideZoomLabelSoon() {
        zoomLabelTask?.cancel()
        zoomLabelTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showZoomLabel = false }
        }
    }

    private func scheduleHideExposureControl() {
        exposureHideTask?.cancel()
        exposureHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { showExposureControl = false }
        }
    }

    // MARK: Light and camera

    /// Raises the display to full brightness behind the white edge gradients.
    ///
    /// Restored on every path out of here — the flip button, the toggle, and
    /// `onDisappear`. That matters more in this process than it does in the
    /// app: the system can suspend a capture extension without warning, and a
    /// phone left at full brightness on the Lock Screen would be a nasty
    /// parting gift.
    private func activateScreenFlash() {
        savedBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 1.0
        withAnimation(.easeIn(duration: 0.1)) { screenFlashOn = true }
    }

    private func deactivateScreenFlash() {
        UIScreen.main.brightness = savedBrightness
        withAnimation(.easeOut(duration: 0.2)) { screenFlashOn = false }
    }

    private func handleCameraFlip() {
        if screenFlashOn { torchOn = false; deactivateScreenFlash() }
        showExposureControl = false
        exposureHideTask?.cancel()
        if camera.isRecording {
            // AVCaptureMovieFileOutput can't switch inputs mid-recording, so
            // the current clip is closed out and `finishRecording` picks the
            // flip back up once the file is written.
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

    // MARK: Recording

    /// Finger down on the shutter: arm hold mode, which a quick release cancels.
    private func handlePressDown() {
        guard holdStartTask == nil, !camera.isRecording, !didCapture else { return }
        holdStartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(holdThreshold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            holdZoomStart = camera.currentZoomFactor
            isHoldRecording = true
            startTimer()
            _ = try? await camera.startRecording()
        }
    }

    /// Finger up: tap or hold, decided by whether hold mode had time to engage.
    private func handleRelease() {
        // The slide-to-lock just engaged — keep recording hands-free and ignore
        // the lift entirely.
        if lockArmed {
            lockArmed = false
            holdStartTask = nil
            return
        }
        // A later tap while locked is what stops the hands-free recording.
        if isLocked {
            isLocked = false
            isHoldRecording = false
            endRecording()
            return
        }
        if let task = holdStartTask {
            task.cancel()
            holdStartTask = nil
            if isHoldRecording {
                isHoldRecording = false
                endRecording()
                lastZoom = camera.currentZoomFactor
                hideZoomLabelSoon()
            } else {
                handleRecordTap()
            }
        } else if camera.isRecording {
            handleRecordTap()
        }
    }

    /// Held and dragged: left toward the lock icon locks hands-free, otherwise
    /// up/down zooms — the same mapping as the in-app shutter.
    private func handleDrag(_ translation: CGSize) {
        guard isHoldRecording, !isLocked else { return }
        if translation.width < -lockSlideThreshold, abs(translation.width) > abs(translation.height) {
            isLocked = true
            lockArmed = true
            withAnimation { showZoomLabel = false }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }
        camera.setZoom(holdZoomStart - translation.height * 0.013)
        zoomLabelTask?.cancel()
        showZoomLabel = true
    }

    private func handleRecordTap() {
        guard !didCapture else { return }
        if camera.isRecording {
            endRecording()
        } else {
            startTimer()
            Task { _ = try? await camera.startRecording() }
        }
    }

    /// Every user-facing way to end a recording goes through here. The stop
    /// tick fires first, synchronously, so it lands on the moment the user
    /// acted rather than the moment AVFoundation finished closing the file.
    private func endRecording() {
        stopHaptic.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            stopHaptic.impactOccurred(intensity: 0.7)
        }
        camera.stopRecording()
        stopTimer()
    }

    private func finishRecording() {
        stopTimer()
        guard pendingCameraFlip else {
            isHoldRecording = false
            isLocked = false
            lockArmed = false
            // The light goes out with the viewfinder. In the app this happens
            // by dismissing the camera screen; here the confirmation stays up,
            // so nothing else would turn it off.
            if screenFlashOn { deactivateScreenFlash() }
            camera.setTorch(false)
            torchOn = false
            withAnimation(.easeOut(duration: 0.25)) { didCapture = true }
            return
        }
        // A flip was asked for mid-recording: the clip just closed is kept —
        // it gets imported like any other — and recording resumes on the other
        // camera if the finger is still down.
        pendingCameraFlip = false
        Task {
            try? await camera.switchCamera()
            holdZoomStart = camera.currentZoomFactor
            guard isHoldRecording else { return }
            startTimer()
            _ = try? await camera.startRecording()
        }
    }

    // MARK: Timer

    private func startTimer() {
        elapsed = 0
        recordingStart = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            // Scheduled on the main run loop, so this body always runs on the
            // main actor — the compiler just can't see that through the
            // nonisolated closure. Asserting it keeps the stop synchronous;
            // hopping via Task would overshoot the duration limit.
            MainActor.assumeIsolated {
                guard let start = recordingStart else { return }
                elapsed = Date().timeIntervalSince(start)
                if !isHoldRecording, !isLocked, elapsed >= durationLimit {
                    endRecording()
                }
            }
        }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    // MARK: Saved state

    private var savedOverlay: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.amber).frame(width: 68, height: 68)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            VStack(spacing: 5) {
                Text("Clip saved")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text("It lands in your project as soon as you unlock.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            // Opening the app is what triggers Face ID / the passcode — the
            // system handles that, not us. Deliberately optional: the clip is
            // already safe on disk, so this is an offer, not a demand.
            Button {
                isOpeningApp = true
                Task { await openApp() }
            } label: {
                Text("Open keep.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(height: 46)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(Theme.paper))
            }
            .buttonStyle(.plain)
            .disabled(isOpeningApp)
            .padding(.horizontal, 44)
            .padding(.top, 6)
        }
        .padding(28)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 24)
        .transition(.opacity)
    }

    @MainActor
    private func openApp() async {
        let activity = NSUserActivity(activityType: NSUserActivityTypeLockedCameraCapture)
        try? await session.openApplication(for: activity)
    }
}

// MARK: - Capture event interaction

/// Bridges the hardware capture buttons (volume keys, Camera Control) into the
/// shutter — and keeps the extension alive.
///
/// The second part is the one that isn't obvious: the system treats a locked
/// capture extension with no `AVCaptureEventInteraction` as idle and suspends
/// it within seconds, which would kill the preview mid-aim.
private struct CaptureEventCatcher: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let interaction = AVCaptureEventInteraction { event in
            guard event.phase == .began else { return }
            action()
        }
        view.addInteraction(interaction)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

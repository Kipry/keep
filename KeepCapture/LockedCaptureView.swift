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

/// The whole locked-camera experience: preview, one shutter, one confirmation.
///
/// Deliberately smaller than the in-app camera. There is no zoom pill, no
/// exposure slider, no torch, no flip-to-front memory — every one of those
/// reads a preference this sandbox cannot see, and none of them is what
/// someone reaching for a locked phone is trying to do. The whole point is
/// that this is over in about a second.
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
    @State private var elapsed: Double = 0
    @State private var timer: Timer?
    @State private var didCapture = false
    @State private var isOpeningApp = false

    private let startHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let stopHaptic  = UIImpactFeedbackGenerator(style: .rigid)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let avSession = camera.session {
                CameraPreviewView(session: avSession)
                    .ignoresSafeArea()
            }

            if didCapture {
                savedOverlay
            } else {
                VStack {
                    destinationChip
                        .padding(.top, 14)
                    Spacer()
                    shutter
                        .padding(.bottom, 44)
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
        // Keeps the hardware capture button (and Camera Control) working — and,
        // just as importantly, tells the system this extension is an active
        // camera experience. Without an AVCaptureEventInteraction the system
        // suspends a locked capture extension after a few idle seconds.
        .background(CaptureEventCatcher { Task { await record() } })
        .task {
            // Session content, not Documents: this extension's own container is
            // wiped on suspension, so anything written there would be gone
            // before the app could ever import it.
            camera.outputDirectory = session.sessionContentURL
            if let handed = try? await KeepCaptureIntent.appContext {
                context = handed
            }
            startHaptic.prepare()
            try? await camera.startSession()
        }
        .onDisappear {
            timer?.invalidate()
            camera.stopSession()
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
    }

    // MARK: Destination

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

    // MARK: Shutter

    private var shutter: some View {
        Button { Task { await record() } } label: {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.32), lineWidth: 4)
                    .frame(width: 78, height: 78)

                // Sweeps shut over the clip's own length, so the wait has a
                // visible end — same read as the in-app shutter.
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.amber, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .fill(camera.isRecording ? Theme.amber : .white)
                    .frame(width: camera.isRecording ? 34 : 62,
                           height: camera.isRecording ? 34 : 62)
                    .animation(.easeInOut(duration: 0.18), value: camera.isRecording)
            }
        }
        .buttonStyle(.plain)
        .disabled(!camera.isRunning || camera.isRecording)
        .accessibilityLabel("Record")
    }

    private var progress: CGFloat {
        guard context.duration > 0 else { return 0 }
        return min(1, CGFloat(elapsed / context.duration))
    }

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

    // MARK: Recording

    private func record() async {
        guard camera.isRunning, !camera.isRecording, !didCapture else { return }
        startHaptic.impactOccurred(intensity: 1.0)
        stopHaptic.prepare()

        elapsed = 0
        let limit = context.duration
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { t in
            Task { @MainActor in
                elapsed += 1.0 / 30
                if elapsed >= limit {
                    t.invalidate()
                    stopHaptic.impactOccurred(intensity: 0.9)
                    camera.stopRecording()
                }
            }
        }

        // Resolves once AVFoundation has finished writing and closing the file,
        // so by the time this returns the clip really is on disk in the session
        // directory — which is the only thing that makes it survivable.
        _ = try? await camera.startRecording()
        timer?.invalidate()
        withAnimation(.easeOut(duration: 0.25)) { didCapture = true }
    }

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

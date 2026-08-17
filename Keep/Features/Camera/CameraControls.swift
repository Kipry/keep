import SwiftUI

// MARK: - Shared camera chrome
//
// The shutter, the duration pills, the exposure slider and the focus ring
// used to live as `private` types inside `CameraView`. They are now shared
// with the locked-capture extension, which runs in its own process and its
// own target and cannot see anything file-private to the app's camera screen.
//
// Shared rather than copied on purpose: two shutters that must behave
// identically but are edited separately is exactly the drift this codebase
// has cleaned up elsewhere. These are pure presentation — they hold no
// camera, no session and no project — so both targets can own one copy.

// MARK: - Record button

/// The shutter. Tap to record a fixed-length clip, hold for a variable one.
///
/// A `DragGesture(minimumDistance: 0)` rather than a `Button`, because the
/// hold interaction needs the finger's whole journey: down starts the hold
/// timer, movement drives zoom and the slide-to-lock, and release decides
/// after the fact whether this was a tap or a hold.
struct RecordButton: View {
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

// MARK: - Duration picker

/// The φ / 1s / 3s / 5s pills under the viewfinder.
///
/// Only ever changes the length of the *next* clip. The stored default lives
/// in Settings; picking a different length here is a one-clip decision, which
/// is also the only kind the locked extension could make — it has no way to
/// write a preference back into the app.
struct DurationPicker: View {
    @Binding var selection: Double

    var body: some View {
        HStack(spacing: 6) {
            ForEach(RecordingDuration.options, id: \.self) { d in
                Button {
                    selection = d
                } label: {
                    Text(verbatim: RecordingDuration.label(d))
                        .font(.mono(13, weight: .medium))
                        .foregroundStyle(selection == d ? Theme.ink : .white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(
                            selection == d ? .white : Color.black.opacity(0.35),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(selection == d ? .clear : .white.opacity(0.4), lineWidth: 1)
                        )
                }
            }
        }
    }
}

// MARK: - Exposure slider

/// The sun handle that appears beside the focus square.
///
/// Reports raw drag translation rather than a bias value: the caller owns the
/// mapping from points to EV, because it also owns the device that has to
/// accept it.
struct ExposureSliderView: View {
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

// MARK: - Focus ring

/// The yellow square that pulses where the user tapped to focus.
struct FocusRingView: View {
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

import SwiftUI
import UIKit

// MARK: - Capture control bar

/// Lens picker and clip length in one capsule above the shutter.
///
/// Only one group is ever open. Tapping the closed one opens it and collapses
/// the other in the same animation, so the bar reads as two halves sliding
/// past each other rather than one control being swapped for another.
///
/// The collapse is a *width* animation, not a fade. A button that fades out
/// leaves its space behind, and the row would look like it was blinking; a
/// button that shrinks to nothing pushes its neighbours along, which is the
/// sideways movement the design asks for. Labels fade on a shorter curve than
/// the width shrinks, so no text is ever drawn squeezed.
struct CaptureControlBar: View {

    enum Group { case lens, duration }

    let stages: [LensStage]
    /// The step the camera is exactly on, or nil when a pinch left it between
    /// two — then nothing is marked, which is the honest state.
    let activeStage: LensStage?
    /// Where the camera actually sits, steps or not — the closed group needs it
    /// to decide which step to stand in for after a pinch.
    let currentZoom: CGFloat
    let duration: Double
    @Binding var expanded: Group
    let isRecording: Bool
    /// Turns each label upright when the phone is held sideways. Applied to
    /// the text only: the buttons keep their shape and the width animation
    /// that folds a group away keeps working along the bar.
    var labelRotation: Angle = .zero
    let onSelectLens: (LensStage) -> Void
    let onSelectDuration: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let buttonHeight: CGFloat = 34
    private let lensWidth: CGFloat = 34
    private let durationWidth: CGFloat = 44
    private let gap: CGFloat = 5

    /// One spring for both directions, so opening and closing are the same
    /// gesture played forwards and backwards.
    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.16)
                     : .spring(response: 0.34, dampingFraction: 0.82)
    }

    var body: some View {
        HStack(spacing: 0) {
            if !stages.isEmpty {
                lensGroup
                divider
            }
            durationGroup
        }
        .padding(gap)
        .background(.black.opacity(0.42), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
        // The bar dims and stops responding while a clip is running: changing
        // the focal length halfway through one would be a cut, not a zoom.
        .opacity(isRecording ? 0.4 : 1)
        .allowsHitTesting(!isRecording)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
    }

    // MARK: Divider

    /// Only drawn between two groups — a bar with no lens picker has nothing
    /// to separate, and a lone hairline would read as a missing control.
    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.16))
            .frame(width: 1, height: 24)
            .padding(.horizontal, gap)
    }

    // MARK: Lens group

    private var lensGroup: some View {
        // Which button leads the row *as drawn* — not which is first in the
        // array. Collapsed onto anything but the first step, indexing by array
        // position gave the one visible button a leading gap with nothing on
        // the other side of it, and the label sat off-centre in the capsule.
        let leading = expanded == .lens ? 0 : (stages.firstIndex { $0 == collapsedStage } ?? 0)
        return HStack(spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                let isActive = activeStage == stage
                // Collapsed, the group still shows one step — the active one,
                // or the nearest if a pinch left us between two. An empty
                // capsule half would look broken.
                let isVisible = expanded == .lens || stage == collapsedStage
                button(
                    label: stage.label(isActive: isActive),
                    width: lensWidth,
                    isActive: isActive,
                    showsBackdrop: isActive,
                    isVisible: isVisible,
                    isFirst: index == leading,
                    index: index
                ) {
                    if expanded == .lens {
                        select(.soft) { onSelectLens(stage) }
                    } else {
                        toggle(to: .lens)
                    }
                }
                .accessibilityLabel(Text("\(String(localized: stage.name)), \(stage.label(isActive: true))"))
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lens")
    }

    /// What the lens half shows when it is closed.
    ///
    /// Between two steps there is no active one, but the group still has to
    /// show something — the nearest step, unhighlighted. It stands for where
    /// the camera is without claiming to be it.
    private var collapsedStage: LensStage? {
        activeStage ?? stages.min {
            abs($0.display - currentZoom) < abs($1.display - currentZoom)
        }
    }

    // MARK: Duration group

    private var durationGroup: some View {
        // Same reason as above, and the one people actually see: with no lens
        // picker — the front camera — the capsule is nothing but this group, so
        // a stray 5pt on the left is the whole bar looking crooked.
        let leading = expanded == .duration
            ? 0
            : (RecordingDuration.options.firstIndex { abs($0 - duration) < 0.001 } ?? 0)
        return HStack(spacing: 0) {
            ForEach(Array(RecordingDuration.options.enumerated()), id: \.element) { index, option in
                let isActive = abs(option - duration) < 0.001
                let isVisible = expanded == .duration || isActive
                button(
                    label: RecordingDuration.label(option),
                    width: durationWidth,
                    isActive: isActive,
                    // Closed, the value is just a label to tap — giving it the
                    // selected pill there would claim a choice is open.
                    showsBackdrop: isActive && expanded == .duration,
                    isVisible: isVisible,
                    isFirst: index == leading,
                    index: index
                ) {
                    if expanded == .duration {
                        select(.soft) { onSelectDuration(option) }
                    } else {
                        toggle(to: .duration)
                    }
                }
                .accessibilityLabel(Text("Recording duration \(RecordingDuration.label(option))"))
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording duration")
    }

    // MARK: Button

    /// A Capsule at 34 × 34 is a circle, so lens and duration buttons need no
    /// separate shape — only a different width.
    private func button(
        label: String,
        width: CGFloat,
        isActive: Bool,
        showsBackdrop: Bool,
        isVisible: Bool,
        isFirst: Bool,
        index: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(.white.opacity(showsBackdrop ? 0.14 : 0))
                Text(verbatim: label)
                    .font(.mono(isActive ? 13 : 12, weight: .medium))
                    .foregroundStyle(isActive ? Theme.amber : .white.opacity(0.72))
                    .fixedSize()
                    .rotationEffect(labelRotation)
                    // Shorter than the width curve, so the label is gone before
                    // its box is, instead of being crushed on the way out.
                    .opacity(isVisible ? 1 : 0)
                    .animation(reduceMotion ? motion : .easeOut(duration: 0.18), value: isVisible)
            }
            .frame(width: isVisible ? width : 0, height: buttonHeight)
            .clipped()
            // The gap has to collapse with the button, or the row would keep
            // the space it was supposed to give up.
            .padding(.leading, isFirst ? 0 : (isVisible ? gap : 0))
            // 34pt is the drawn size; the touch target has to be 44. Padding
            // out and back leaves the layout untouched and the hit area right.
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .padding(.vertical, -5)
        }
        .buttonStyle(.plain)
        .animation(motion.delay(reduceMotion ? 0 : Double(index) * 0.025), value: isVisible)
    }

    // MARK: Actions

    private func toggle(to group: Group) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(motion) { expanded = group }
    }

    /// Applies the value, then lets the choice be seen before the bar folds
    /// itself back up. Snapping shut on the same frame reads as a rejection.
    private func select(_ style: UIImpactFeedbackGenerator.FeedbackStyle,
                        _ apply: @escaping () -> Void) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        apply()
        guard expanded == .duration else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(motion) { expanded = .lens }
        }
    }
}

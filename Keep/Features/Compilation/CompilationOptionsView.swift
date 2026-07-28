import SwiftUI

struct CompilationOptionsView: View {
    @Binding var transition: TransitionStyle
    @Binding var quality: ExportQuality
    let clipCount: Int
    let onExport: () -> Void

    @Environment(\.dismiss) private var dismiss

    // Key must match RecordingQuality.defaultsKey.
    @AppStorage("recordingQuality") private var recordingQualityRaw = RecordingQuality.p1080.rawValue

    @State private var holdProgress: CGFloat = 0
    @State private var isHolding = false
    @State private var holdTask: Task<Void, Never>?

    private var recordingQuality: RecordingQuality {
        RecordingQuality(rawValue: recordingQualityRaw) ?? .p1080
    }

    /// Only worth asking when the footage can actually carry the difference.
    /// Recording at 1080p leaves 4K as an upscale — four times the file for
    /// nothing — so the card goes away rather than offering a false choice.
    private var offersQualityChoice: Bool { recordingQuality.exportChoices.count > 1 }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        transitionCard
                        if offersQualityChoice {
                            qualityCard
                        } else {
                            fixedQualityNote
                        }
                        summaryRow
                    }
                    // With the quality card gone the page sits top-heavy, so
                    // the remaining card drops towards the middle.
                    .padding(.top, offersQualityChoice ? 0 : 64)
                    .padding(.bottom, 140)
                }
            }

            VStack {
                Spacer()
                holdToExportButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .accessibilityLabel("Close")
            Spacer()
            Text("EXPORT")
                .font(.eyebrow)
                .tracking(3)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 28)
    }

    // MARK: - Transition card

    private var transitionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("TRANSITION")

            HStack(spacing: 12) {
                ForEach(TransitionStyle.allCases) { style in
                    transitionCell(style)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    private func transitionCell(_ style: TransitionStyle) -> some View {
        let isSelected = transition == style
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { transition = style }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    if style == .cut {
                        HStack(spacing: 2) {
                            Rectangle().fill(Theme.amber.opacity(0.6))
                            Rectangle().fill(.white.opacity(0.22))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        LinearGradient(
                            colors: [Theme.amber.opacity(0.6), .white.opacity(0.22)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .frame(height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Theme.amber : .white.opacity(0.1),
                                lineWidth: isSelected ? 2 : 1)
                )

                Text(style.rawValue)
                    .font(.mono(11, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.4))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quality card

    private var qualityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("QUALITY")

            HStack(spacing: 12) {
                ForEach(recordingQuality.exportChoices) { q in
                    qualityCell(q)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
    }

    private func qualityCell(_ q: ExportQuality) -> some View {
        let isSelected = quality == q
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { quality = q }
        } label: {
            VStack(spacing: 6) {
                Text(q.rawValue)
                    .font(.hand(22))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.28))
                Text(q == .p4K ? "Largest file" : "Smaller file")
                    .font(.monoCaption)
                    .foregroundStyle(isSelected ? .white.opacity(0.55) : .white.opacity(0.18))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                isSelected ? Theme.amber.opacity(0.14) : .white.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.amber : .white.opacity(0.08),
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Stands in for the quality card, so the absent choice reads as a decision
    /// already made rather than a missing control.
    private var fixedQualityNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "gearshape")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
            Text("Exporting in 1080p — the resolution your clips are recorded at. Switch to 4K under Settings › Recording.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "film.stack")
                .foregroundStyle(.white.opacity(0.28))
            Text("\(clipCount) clip\(clipCount == 1 ? "" : "s") → 1 video")
                .font(.monoCaption)
                .foregroundStyle(.white.opacity(0.28))
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }

    // MARK: - Hold-to-export button

    private var holdToExportButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.amber.opacity(0.18))
                .frame(height: 64)

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 18)
                    .fill(Theme.amber)
                    .frame(width: geo.size.width * holdProgress)
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            HStack(spacing: 10) {
                Image(systemName: holdProgress > 0.02 ? "arrow.right.circle.fill" : "hand.tap.fill")
                    .font(.body.bold())
                Text(holdProgress > 0.02 ? "Keep holding…" : "Hold to Export")
                    .font(.hand(18))
            }
            .foregroundStyle(holdProgress > 0.55 ? Theme.ink : .white)
            .animation(.easeInOut(duration: 0.2), value: holdProgress > 0.55)
        }
        .frame(height: 64)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isHolding else { return }
                    isHolding = true
                    startHold()
                }
                .onEnded { _ in cancelHold() }
        )
    }

    // MARK: - Hold logic

    // 35 % shorter than the original 2.4 s → 1.56 s.
    // A single withAnimation drives the fill at native frame rate (60/120 fps)
    // instead of stepping at 25 fps, which was the source of the jitter.
    private static let holdDuration: Double = 1.56

    private func startHold() {
        withAnimation(.linear(duration: Self.holdDuration)) {
            holdProgress = 1.0
        }
        holdTask = Task {
            try? await Task.sleep(
                nanoseconds: UInt64(Self.holdDuration * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismiss()
                onExport()
            }
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        withAnimation(.spring(response: 0.35)) { holdProgress = 0 }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.eyebrow)
            .tracking(2)
            .foregroundStyle(.white.opacity(0.35))
            .padding(.horizontal, 20)
    }
}

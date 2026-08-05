import SwiftUI

struct ExportProgressOverlay: View {
    let clips: [Clip]
    let progress: Double   // 0.0 – 1.0
    /// Nil hides the cancel control. Without one this overlay was a dead end:
    /// an opaque, hit-testing backdrop with no way out, so a long 4K export
    /// locked the screen for minutes.
    var onCancel: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            // Ambient amber glow behind the strip
            RadialGradient(
                colors: [Theme.amber.opacity(0.12), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 200
            )
            .frame(width: 400, height: 400)
            .allowsHitTesting(false)

            VStack(spacing: 52) {
                filmStrip

                VStack(spacing: 22) {
                    Text("COMPILING YOUR REEL")
                        .font(.eyebrow)
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.38))

                    progressBar

                    Text("\(Int(progress * 100))%")
                        .font(.hand(52))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.08), value: Int(progress * 100))
                        .monospacedDigit()

                    if let onCancel {
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 11)
                                .background(.white.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 40)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Film strip

    private var filmStrip: some View {
        let shown = Array(clips.prefix(5))
        return VStack(spacing: 0) {
            sprocketRow
            HStack(spacing: 3) {
                ForEach(shown) { clip in
                    clipCell(clip)
                }
                // Pad to 5 cells so the strip is always full width
                if shown.count < 5 {
                    ForEach(0..<(5 - shown.count), id: \.self) { _ in
                        Rectangle()
                            .fill(.white.opacity(0.05))
                            .frame(width: cellWidth, height: cellHeight)
                    }
                }
            }
            .padding(.horizontal, 6)
            .overlay(shimmer)
            sprocketRow
        }
        .background(Theme.filmCard)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 20)
    }

    private var cellWidth:  CGFloat { 60 }
    private var cellHeight: CGFloat { 80 }

    private func clipCell(_ clip: Clip) -> some View {
        Group {
            if let data = clip.thumbnailData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.white.opacity(0.07))
            }
        }
        .frame(width: cellWidth, height: cellHeight)
        .clipped()
    }

    // Amber light that sweeps left-to-right as progress advances
    @ViewBuilder
    private var shimmer: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, Theme.amber.opacity(0.45), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 72)
            .offset(x: (geo.size.width + 72) * CGFloat(progress) - 36)
            .animation(.linear(duration: 0.08), value: progress)
            .blendMode(.screen)
        }
    }

    private var sprocketRow: some View {
        HStack(spacing: 4) {
            ForEach(0..<14, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.background)
                    .frame(width: 8, height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.1))
                    .frame(height: 3)
                Capsule()
                    .fill(Theme.amber)
                    .frame(width: geo.size.width * CGFloat(progress), height: 3)
                    .shadow(color: Theme.amber.opacity(0.8), radius: 6)
                    .animation(.linear(duration: 0.08), value: progress)
            }
        }
        .frame(height: 3)
    }
}

// MARK: - Saved confirmation

/// Confirms that the export actually landed in the photo library.
///
/// The evidence comes from `UIActivityViewController`'s completion handler,
/// which reports the chosen activity and whether it finished — the app already
/// received both and threw them away. `.saveToCameraRoll` completing is proof
/// enough; anything stronger would mean asking for read access to the photo
/// library purely to look, and a permission prompt is too high a price for a
/// confirmation.
struct ExportSavedOverlay: View {
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ring: CGFloat = 0
    @State private var tick: CGFloat = 0
    @State private var captionIn = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            RadialGradient(colors: [Theme.amber.opacity(0.14), .clear],
                           center: .center, startRadius: 0, endRadius: 190)
                .frame(width: 380, height: 380)
                .allowsHitTesting(false)

            VStack(spacing: 30) {
                ZStack {
                    Circle()
                        .trim(from: 0, to: ring)
                        .stroke(Theme.amber, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 96, height: 96)
                    Checkmark()
                        .trim(from: 0, to: tick)
                        .stroke(Theme.paper, style: StrokeStyle(lineWidth: 4.5,
                                                                lineCap: .round, lineJoin: .round))
                        .frame(width: 46, height: 36)
                }

                VStack(spacing: 8) {
                    Text("Saved to Photos")
                        .font(.hand(30))
                        .foregroundStyle(.white)
                    Text("YOUR VIDEO IS IN YOUR LIBRARY")
                        .font(.eyebrow)
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.35))
                }
                .opacity(captionIn ? 1 : 0)
                .offset(y: captionIn ? 0 : 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onAppear(perform: play)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Saved to Photos"))
    }

    private func play() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard !reduceMotion else {
            ring = 1; tick = 1; captionIn = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { onDismiss() }
            return
        }
        // The ring closes, the tick is drawn into it, the words arrive last —
        // one gesture in three beats rather than three things appearing.
        withAnimation(.easeOut(duration: 0.42)) { ring = 1 }
        withAnimation(.easeOut(duration: 0.3).delay(0.34)) { tick = 1 }
        withAnimation(.easeOut(duration: 0.28).delay(0.5)) { captionIn = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { onDismiss() }
    }
}

/// Drawn as a single stroke so `trim` sweeps it on in one continuous motion.
private struct Checkmark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

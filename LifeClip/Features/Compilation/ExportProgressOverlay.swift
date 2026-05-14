import SwiftUI

struct ExportProgressOverlay: View {
    let clips: [Clip]
    let progress: Double   // 0.0 – 1.0

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

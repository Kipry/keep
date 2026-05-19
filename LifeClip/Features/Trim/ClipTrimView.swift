import SwiftUI
import AVFoundation

struct ClipTrimView: View {
    @Bindable var clip: Clip
    let onDismiss: () -> Void

    @State private var player: AVPlayer?
    @State private var duration: Double = 1
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 1
    @State private var currentTime: Double = 0
    @State private var isPlaying = false
    @State private var thumbnails: [UIImage] = []
    @State private var timeObserver: Any?

    // MARK: Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 52)

                videoPreview
                    .frame(maxHeight: .infinity)

                VStack(spacing: 14) {
                    TrimScrubber(
                        thumbnails: thumbnails,
                        duration: duration,
                        trimStart: $trimStart,
                        trimEnd: $trimEnd,
                        currentTime: currentTime,
                        onSeek: seekTo
                    )
                    .frame(height: 62)
                    .padding(.horizontal, 20)

                    timeRow
                        .padding(.horizontal, 24)
                }
                .padding(.top, 20)
                .padding(.bottom, 20)

                playPauseButton
                    .padding(.bottom, 52)
            }
        }
        .onAppear { setup() }
        .onDisappear { cleanup() }
    }

    // MARK: Subviews

    private var topBar: some View {
        HStack {
            Button("Abbrechen") { onDismiss() }
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Text("Trimmen")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Button("Fertig") { save() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.amber)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var videoPreview: some View {
        ZStack {
            if let p = player {
                TrimPlayerView(player: p)
                    .onTapGesture { togglePlay() }
            }
            if !isPlaying {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.white.opacity(0.55))
                    .allowsHitTesting(false)
            }
        }
    }

    private var timeRow: some View {
        HStack {
            label(formatTime(trimStart), color: Theme.amber)
            Spacer()
            label(formatTime(trimEnd - trimStart), color: .white)
            Spacer()
            label(formatTime(trimEnd), color: Theme.amber)
        }
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.mono(12, weight: .medium))
            .foregroundStyle(color)
    }

    private var playPauseButton: some View {
        Button { togglePlay() } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.1), in: Circle())
        }
    }

    // MARK: Actions

    private func setup() {
        trimStart = clip.trimStart
        trimEnd   = clip.trimEnd ?? clip.duration
        duration  = max(clip.duration, 0.1)

        let p = AVPlayer(url: clip.fileURL)
        player = p
        seekTo(trimStart)

        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak p] time in
            guard let p else { return }
            currentTime = time.seconds
            if currentTime >= trimEnd {
                p.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600))
                if isPlaying { p.play() }
            }
        }

        Task { await generateThumbnails() }
    }

    private func cleanup() {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        player?.pause()
        player = nil
    }

    private func togglePlay() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            if currentTime >= trimEnd { seekTo(trimStart) }
            p.play()
            isPlaying = true
        }
    }

    private func seekTo(_ time: Double) {
        let t = CMTime(seconds: max(0, min(duration, time)), preferredTimescale: 600)
        player?.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func save() {
        clip.trimStart = trimStart
        // nil means "play to end" — avoids storing floating-point noise at duration boundary
        clip.trimEnd = trimEnd >= duration - 0.05 ? nil : trimEnd
        onDismiss()
    }

    private func generateThumbnails() async {
        let asset = AVURLAsset(url: clip.fileURL)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 120, height: 120)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter  = CMTime(seconds: 0.1, preferredTimescale: 600)

        let count = 9
        var result: [UIImage] = []
        for i in 0..<count {
            let t = CMTime(seconds: Double(i) / Double(count - 1) * duration,
                           preferredTimescale: 600)
            if let img = try? await withCheckedThrowingContinuation(
                { (c: CheckedContinuation<UIImage, Error>) in
                    gen.generateCGImageAsynchronously(for: t) { cg, _, err in
                        if let cg { c.resume(returning: UIImage(cgImage: cg)) }
                        else { c.resume(throwing: err ?? NSError(domain: "", code: 0)) }
                    }
                }) {
                result.append(img)
            }
        }
        thumbnails = result
    }

    private func formatTime(_ t: Double) -> String {
        let s = max(0, t)
        if s < 60 { return String(format: "%.1fs", s) }
        return String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }
}

// MARK: - TrimScrubber

private struct TrimScrubber: View {
    let thumbnails: [UIImage]
    let duration: Double
    @Binding var trimStart: Double
    @Binding var trimEnd: Double
    let currentTime: Double
    let onSeek: (Double) -> Void

    private let handleW: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let leftX  = CGFloat(trimStart / duration) * w
            let rightX = CGFloat(trimEnd   / duration) * w
            let playX  = CGFloat(max(trimStart, min(trimEnd, currentTime)) / duration) * w

            ZStack(alignment: .leading) {
                // Frame thumbnails
                HStack(spacing: 0) {
                    if thumbnails.isEmpty {
                        Color.white.opacity(0.1)
                    } else {
                        ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: w / CGFloat(thumbnails.count), height: h)
                                .clipped()
                        }
                    }
                }

                // Dim: before trim start
                Color.black.opacity(0.62)
                    .frame(width: max(0, leftX))
                    .frame(maxHeight: .infinity, alignment: .leading)

                // Dim: after trim end
                Color.black.opacity(0.62)
                    .frame(width: max(0, w - rightX))
                    .frame(maxHeight: .infinity, alignment: .trailing)

                // Amber top border of selection
                Theme.amber
                    .frame(width: max(0, rightX - leftX), height: 3)
                    .offset(x: leftX)
                    .frame(maxHeight: .infinity, alignment: .top)

                // Amber bottom border
                Theme.amber
                    .frame(width: max(0, rightX - leftX), height: 3)
                    .offset(x: leftX)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                // Left bracket handle
                handle(chevron: "chevron.compact.left")
                    .offset(x: max(0, leftX - handleW / 2))

                // Right bracket handle
                handle(chevron: "chevron.compact.right")
                    .offset(x: min(w - handleW / 2, rightX - handleW / 2))

                // Playhead
                Rectangle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 2, height: h)
                    .offset(x: playX - 1)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x     = value.location.x
                        let start = value.startLocation.x
                        let t     = Double(x / w) * duration

                        if start <= leftX + handleW + 4 {
                            trimStart = max(0, min(trimEnd - 0.2, t))
                            onSeek(trimStart)
                        } else if start >= rightX - handleW - 4 {
                            trimEnd = max(trimStart + 0.2, min(duration, t))
                            onSeek(trimEnd)
                        } else {
                            onSeek(max(trimStart, min(trimEnd, t)))
                        }
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func handle(chevron: String) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Theme.amber)
            .frame(width: handleW)
            .frame(maxHeight: .infinity)
            .overlay(
                Image(systemName: chevron)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.ink)
            )
    }
}

// MARK: - TrimPlayerView

private struct TrimPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> _PlayerUIView { _PlayerUIView() }
    func updateUIView(_ view: _PlayerUIView, context: Context) { view.layer_.player = player }

    class _PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var layer_: AVPlayerLayer { layer as! AVPlayerLayer }
        override init(frame: CGRect) {
            super.init(frame: frame)
            layer_.videoGravity = .resizeAspect
            backgroundColor = .black
        }
        required init?(coder: NSCoder) { fatalError() }
    }
}

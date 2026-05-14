import SwiftUI
import AVFoundation

struct ProjectPlayerView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 1
    @State private var isDragging = false
    @State private var isSeeking = false
    @State private var scrubTarget: Double? = nil
    @State private var wasPlayingBeforeScrub = false
    @State private var timeObserver: Any?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoLayerView(player: player)
                    .ignoresSafeArea()
                    .onTapGesture { togglePlayback() }
            } else {
                ProgressView().tint(.white).scaleEffect(1.5)
            }

            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .task { await buildCompositionAndPlay() }
        .onDisappear { teardown() }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.5), in: Circle())
            }
            Spacer()
            VStack(spacing: 2) {
                Text(project.name)
                    .font(.navTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(project.activeClips.count) CLIPS · \(timeString(duration))")
                    .font(.monoCaption)
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 14) {
            scrubBar

            HStack {
                Text(timeString(currentTime))
                    .font(.monoCaption)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 38, alignment: .leading)
                    .monospacedDigit()

                Spacer()

                Button { togglePlayback() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }

                Spacer()

                Text(timeString(duration))
                    .font(.monoCaption)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 38, alignment: .trailing)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 48)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -40)
        )
    }

    // MARK: - Scrub bar

    private var scrubBar: some View {
        GeometryReader { geo in
            let progress = duration > 0 ? min(currentTime / duration, 1.0) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(height: 3)
                Capsule()
                    .fill(Theme.amber)
                    .frame(width: geo.size.width * CGFloat(progress), height: 3)
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: geo.size.width * CGFloat(progress) - 7)
            }
            .frame(height: 20, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        // Pause once at the start of a scrub so frames update instantly
                        if !isDragging {
                            isDragging = true
                            wasPlayingBeforeScrub = player?.timeControlStatus == .playing
                            player?.pause()
                            isPlaying = false
                        }
                        let p = max(0, min(1, val.location.x / geo.size.width))
                        currentTime = p * duration
                        // Queue a seek; performScrubSeek() chains them so only one
                        // is in flight at a time, dropping intermediate targets.
                        scrubTarget = currentTime
                        performScrubSeek()
                    }
                    .onEnded { val in
                        let p = max(0, min(1, val.location.x / geo.size.width))
                        currentTime = p * duration
                        // Final precise seek, then optionally resume playback
                        player?.seek(
                            to: CMTime(seconds: currentTime, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: .zero
                        ) { finished in
                            guard finished else { return }
                            DispatchQueue.main.async {
                                isDragging = false
                                isSeeking = false
                                scrubTarget = nil
                                if wasPlayingBeforeScrub {
                                    player?.play()
                                    isPlaying = true
                                }
                            }
                        }
                    }
            )
        }
        .frame(height: 20)
    }

    // MARK: - Actions

    private func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause(); isPlaying = false
        } else {
            player.play(); isPlaying = true
        }
    }

    // Throttled seek chain: only one seek in flight at a time.
    // When a seek completes, checks if a newer target arrived and issues it.
    private func performScrubSeek() {
        guard !isSeeking, let target = scrubTarget else { return }
        isSeeking = true
        scrubTarget = nil
        player?.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: 600),
            toleranceAfter:  CMTime(seconds: 0.1, preferredTimescale: 600)
        ) { finished in
            guard finished else { return }
            DispatchQueue.main.async {
                isSeeking = false
                performScrubSeek()   // drain any queued target
            }
        }
    }

    private func teardown() {
        player?.pause()
        if let obs = timeObserver { player?.removeTimeObserver(obs); timeObserver = nil }
    }

    // MARK: - Composition

    private func buildCompositionAndPlay() async {
        let clips = project.activeClips.filter { $0.isAvailable }
        guard !clips.isEmpty else { return }

        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audioTrack = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return }

        var cursor = CMTime.zero
        var firstAsset: AVURLAsset?

        for clip in clips {
            let asset = AVURLAsset(url: clip.fileURL)
            guard
                let dur = try? await asset.load(.duration),
                let srcVideo = try? await asset.loadTracks(withMediaType: .video).first
            else { continue }

            let range = CMTimeRange(start: .zero, duration: dur)
            try? videoTrack.insertTimeRange(range, of: srcVideo, at: cursor)
            if let srcAudio = try? await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: srcAudio, at: cursor)
            }
            if firstAsset == nil { firstAsset = asset }
            cursor = CMTimeAdd(cursor, dur)
        }

        if let first = firstAsset,
           let track = try? await first.loadTracks(withMediaType: .video).first,
           let transform = try? await track.load(.preferredTransform) {
            videoTrack.preferredTransform = transform
        }

        let totalDuration = cursor.seconds
        let item = AVPlayerItem(asset: composition)
        let newPlayer = AVPlayer(playerItem: item)
        duration = totalDuration

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !self.isDragging else { return }
            self.currentTime = time.seconds
        }

        player = newPlayer
        newPlayer.play()
    }

    // MARK: - Helpers

    private func timeString(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - VideoLayerView
// Shared by ProjectPlayerView and FilmCell preview — plain AVPlayerLayer,
// no AVKit chrome (no AirPlay, no speed control).

struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        view.playerLayer.player = player
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

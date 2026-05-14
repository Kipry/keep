import SwiftUI
import AVFoundation

struct ProjectPlayerView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

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

            overlay
        }
        .task { await buildCompositionAndPlay() }
        .onDisappear { player?.pause() }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    // MARK: - Overlay

    private var overlay: some View {
        VStack {
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
                    Text("\(project.activeClips.count) CLIPS · \(durationText)")
                        .font(.monoCaption)
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                // Balance the back button so the title stays centred
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()
        }
    }

    // MARK: - Playback

    private func togglePlayback() {
        guard let player else { return }
        player.timeControlStatus == .playing ? player.pause() : player.play()
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
                let duration = try? await asset.load(.duration),
                let srcVideo = try? await asset.loadTracks(withMediaType: .video).first
            else { continue }

            let range = CMTimeRange(start: .zero, duration: duration)
            try? videoTrack.insertTimeRange(range, of: srcVideo, at: cursor)

            if let srcAudio = try? await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: srcAudio, at: cursor)
            }

            if firstAsset == nil { firstAsset = asset }
            cursor = CMTimeAdd(cursor, duration)
        }

        // Carry the preferred rotation transform from the first clip
        if let first = firstAsset,
           let track = try? await first.loadTracks(withMediaType: .video).first,
           let transform = try? await track.load(.preferredTransform) {
            videoTrack.preferredTransform = transform
        }

        let newPlayer = AVPlayer(playerItem: AVPlayerItem(asset: composition))
        player = newPlayer
        newPlayer.play()
    }

    // MARK: - Helpers

    private var durationText: String {
        let t = project.totalDuration
        return t < 60
            ? String(format: "%.0fs", t)
            : String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - VideoLayerView

private struct VideoLayerView: UIViewRepresentable {
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

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

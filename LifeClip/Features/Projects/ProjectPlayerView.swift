import SwiftUI
import AVKit

/// Plays all active clips of a project back-to-back using AVQueuePlayer.
/// No export step required — clips are streamed directly from the sandbox.
struct ProjectPlayerView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVQueuePlayer?
    @State private var isReady = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player, isReady {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }

            // Overlay: close button + title
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.5), in: Circle())
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text(project.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("\(project.activeClips.count) clips · \(durationText)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    // Mirror close button for centering
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()
            }
        }
        .task { setupPlayer() }
        .onDisappear { player?.pause() }
    }

    // MARK: - Setup

    private func setupPlayer() {
        let clips = project.activeClips
        guard !clips.isEmpty else { return }

        // Filter to clips whose files actually exist so we don't hit a broken item
        let items = clips
            .filter { $0.isAvailable }
            .map { AVPlayerItem(url: $0.fileURL) }

        guard !items.isEmpty else { return }

        let queuePlayer = AVQueuePlayer(items: items)
        player = queuePlayer
        isReady = true
        queuePlayer.play()
    }

    // MARK: - Helpers

    private var durationText: String {
        let total = project.totalDuration
        if total < 60 { return String(format: "%.0fs", total) }
        return String(format: "%d:%02d", Int(total) / 60, Int(total) % 60)
    }
}

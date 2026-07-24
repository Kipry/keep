import SwiftUI
import AVKit

/// Grid cell showing a clip thumbnail, duration badge, and a tap-to-preview player.
struct ClipCell: View {
    let clip: Clip

    @State private var isPreviewPresented = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Thumbnail or fallback
            Group {
                if let data = clip.thumbnailData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color(.secondarySystemBackground))
                        .overlay {
                            Image(systemName: "film")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Duration badge
            Text(durationText)
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                .padding(6)

            // Unavailable overlay
            if !clip.isAvailable {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.5))
                    .overlay {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.yellow)
                    }
            }
        }
        .onTapGesture { isPreviewPresented = true }
        .sheet(isPresented: $isPreviewPresented) {
            ClipPlayerView(url: clip.fileURL)
                .presentationDetents([.medium, .large])
        }
    }

    private var durationText: String {
        let d = clip.duration
        return d < 60
            ? String(format: "%.0fs", d)
            : String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)
    }
}

// MARK: - ClipPlayerView

private struct ClipPlayerView: View {
    let url: URL

    var body: some View {
        VideoPlayer(player: AVPlayer(url: url))
            .ignoresSafeArea(edges: .bottom)
    }
}

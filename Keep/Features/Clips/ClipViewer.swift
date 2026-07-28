import AVFoundation
import SwiftUI
import UIKit

// MARK: - ClipThumbCell

/// Small tappable clip thumbnail used wherever a set of clips is listed —
/// the memories lookback rows, the streak day card and the place sheet.
struct ClipThumbCell: View {
    let clip: Clip
    let onTap: () -> Void
    @State private var thumb: UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.13))

                if let thumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: clip.isPhoto ? "photo" : "film")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.18))
                }

                // Photo badge so imported stills read differently from video clips.
                if clip.isPhoto {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                Text(clip.createdAt, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                    .padding(5)
            }
            .frame(width: 72, height: 96)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .task(id: clip.id) { await loadThumb() }
    }

    private func loadThumb() async {
        if let data = clip.thumbnailData, let img = UIImage(data: data) {
            thumb = img; return
        }
        // Photo clips: load the original still directly — most reliable preview.
        if clip.isPhoto, let url = clip.photoSourceURL, let img = UIImage(contentsOfFile: url.path) {
            thumb = img; return
        }
        guard clip.isAvailable else { return }
        let asset = AVURLAsset(url: clip.fileURL)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 160, height: 160)
        let t = CMTime(seconds: clip.trimStart, preferredTimescale: 600)
        if let cg = try? await withCheckedThrowingContinuation(
            { (c: CheckedContinuation<CGImage, Error>) in
                gen.generateCGImageAsynchronously(for: t) { img, _, err in
                    if let img { c.resume(returning: img) }
                    else { c.resume(throwing: err ?? NSError(domain: "", code: 0)) }
                }
            }) {
            thumb = UIImage(cgImage: cg)
        }
    }
}

// MARK: - ClipViewer

/// Fullscreen, swipeable viewer for a set of clips. Photos show their original
/// still image; videos play in an AVPlayer. Each page is pinch-zoomable.
struct ClipViewer: View {
    let clips: [Clip]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var players: [UUID: AVPlayer] = [:]

    init(clips: [Clip], initialIndex: Int) {
        self.clips = clips
        self.initialIndex = initialIndex
        _index = State(initialValue: min(max(initialIndex, 0), max(clips.count - 1, 0)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(clips.indices, id: \.self) { i in
                    page(for: clips[i], i: i)
                        .tag(i)
                        .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                    if clips.count > 1 {
                        Text("\(index + 1) / \(clips.count)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.4), in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                if index < clips.count {
                    let clip = clips[index]
                    HStack(spacing: 6) {
                        Text(clip.createdAt, format: .dateTime.day().month().year().locale(Locale.current))
                        Text(clip.createdAt, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                            .fontDesign(.monospaced)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 32)
                }
            }
        }
        .onChange(of: index) { old, new in
            if old < clips.count { players[clips[old].id]?.pause() }
            if new < clips.count { play(clips[new]) }
        }
        .onAppear { PlaybackAudio.activate() }   // audible over the silent switch
        .onDisappear { PlaybackAudio.deactivate() }
    }

    @ViewBuilder
    private func page(for clip: Clip, i: Int) -> some View {
        if clip.isPhoto {
            Zoomable(isActive: i == index) {
                ZStack {
                    Color.black
                    if let img = photoImage(clip) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                    }
                }
            }
        } else {
            // Play/pause is handed to Zoomable rather than attached here, so it
            // can be made to wait on the double-tap-to-zoom recogniser.
            Zoomable(isActive: i == index, onSingleTap: { togglePlayback(clip) }) {
                ZStack {
                    Color.black
                    if let player = players[clip.id] {
                        VideoLayerView(player: player)
                    }
                }
            }
            .onAppear {
                if players[clip.id] == nil {
                    let item = AVPlayerItem(url: clip.fileURL)
                    if let trimEnd = clip.trimEnd {
                        item.forwardPlaybackEndTime = CMTime(seconds: trimEnd, preferredTimescale: 600)
                    }
                    let p = AVPlayer(playerItem: item)
                    players[clip.id] = p
                    if i == index { play(clip) }
                }
            }
            .onDisappear { players[clip.id]?.pause() }
        }
    }

    private func togglePlayback(_ clip: Clip) {
        guard let player = players[clip.id] else { return }
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
    }

    private func play(_ clip: Clip) {
        guard let player = players[clip.id] else { return }
        player.seek(to: CMTime(seconds: clip.trimStart, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    private func photoImage(_ clip: Clip) -> UIImage? {
        if let url = clip.photoSourceURL, let img = UIImage(contentsOfFile: url.path) { return img }
        if let data = clip.thumbnailData { return UIImage(data: data) }
        return nil
    }
}

import SwiftUI
import SwiftData
import AVFoundation

struct OnThisDayView: View {
    @Query(filter: #Predicate<Clip> { !$0.isDeleted }) private var allClips: [Clip]

    private var grouped: [(year: Int, clips: [Clip])] {
        let cal = Calendar.current
        let today = Date()
        let currentYear = cal.component(.year, from: today)
        let month = cal.component(.month, from: today)
        let day   = cal.component(.day,   from: today)

        let matching = allClips.filter { clip in
            if let proj = clip.project, proj.isDeleted { return false }
            let c = cal.dateComponents([.year, .month, .day], from: clip.createdAt)
            return c.month == month && c.day == day && c.year != currentYear
        }

        let byYear = Dictionary(grouping: matching) { cal.component(.year, from: $0.createdAt) }
        return byYear.keys.sorted(by: >).map { (year: $0, clips: byYear[$0]!) }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if grouped.isEmpty {
                emptyState
            } else {
                scrollContent
            }
        }
    }

    // MARK: Scroll content

    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header.padding(.horizontal, 20)

                ForEach(grouped, id: \.year) { entry in
                    yearSection(year: entry.year, clips: entry.clips)
                }
            }
            .padding(.top, 60)
            .padding(.bottom, 120)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("An diesem Tag")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            Text(formattedDate)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "d. MMMM"
        f.locale = Locale(identifier: "de_DE")
        return f.string(from: Date())
    }

    // MARK: Year section

    private func yearSection(year: Int, clips: [Clip]) -> some View {
        let yearsAgo  = Calendar.current.component(.year, from: Date()) - year
        let sectionLabel = yearsAgo == 1 ? "Vor 1 Jahr" : "Vor \(yearsAgo) Jahren"

        return VStack(alignment: .leading, spacing: 10) {
            Text(sectionLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .tracking(0.8)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(clips.sorted { $0.order < $1.order }) { clip in
                        DayClipCell(clip: clip)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(Theme.amber.opacity(0.55))
            Text("Noch keine Erinnerungen")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Text("Clips, die du heute in\nvergangenen Jahren aufgenommen hast,\nerscheinen hier.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - DayClipCell

private struct DayClipCell: View {
    let clip: Clip

    @State private var thumb: UIImage?
    @State private var player: AVPlayer?
    @State private var isPlaying = false

    private let w: CGFloat = 108
    private let h: CGFloat = 152

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.13))

            thumbLayer
            durationBadge
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task { await loadThumb() }
    }

    private var thumbLayer: some View {
        Group {
            if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "film")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
        .frame(width: w, height: h)
    }

    private var durationBadge: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text(formatDuration(clip.effectiveDuration))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }
        }
        .frame(width: w, height: h)
    }

    private func loadThumb() async {
        if let data = clip.thumbnailData, let img = UIImage(data: data) {
            thumb = img
            return
        }
        let asset = AVURLAsset(url: clip.fileURL)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 220, height: 220)
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

    private func formatDuration(_ d: Double) -> String {
        if d < 60 { return String(format: "%.0fs", d) }
        return String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)
    }
}

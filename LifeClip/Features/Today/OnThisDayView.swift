import SwiftUI
import SwiftData
import AVFoundation

struct OnThisDayView: View {
    @Query(filter: #Predicate<Clip> { !$0.isDeleted })
    private var allClips: [Clip]

    @Query(filter: #Predicate<Project> { !$0.isDeleted })
    private var projects: [Project]

    @State private var showSettings = false

    private var cal: Calendar { .current }
    private var today: Date { cal.startOfDay(for: Date()) }

    // MARK: - Stats

    private var recordingDays: Int {
        Set(allClips.map { cal.startOfDay(for: $0.createdAt) }).count
    }

    private var totalDurationLabel: String {
        let t = allClips.reduce(0.0) { $0 + $1.effectiveDuration }
        if t < 60   { return String(format: "%.0fs", t) }
        if t < 3600 { return String(format: "%dm", Int(t) / 60) }
        return String(format: "%dh %dm", Int(t) / 3600, (Int(t) % 3600) / 60)
    }

    // MARK: - Streak

    private var uniqueRecordingDays: [Date] {
        Set(allClips.map { cal.startOfDay(for: $0.createdAt) }).sorted(by: >)
    }

    private var currentStreak: Int {
        let days = uniqueRecordingDays
        guard let most = days.first else { return 0 }
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        guard most == today || most == yesterday else { return 0 }
        var streak = 1, cur = most
        for day in days.dropFirst() {
            guard day == cal.date(byAdding: .day, value: -1, to: cur)! else { break }
            streak += 1; cur = day
        }
        return streak
    }

    private var bestStreak: Int {
        let days = uniqueRecordingDays
        guard !days.isEmpty else { return 0 }
        var best = 1, cur = 1
        for i in 1..<days.count {
            if days[i] == cal.date(byAdding: .day, value: -1, to: days[i - 1])! {
                cur += 1; best = max(best, cur)
            } else { cur = 1 }
        }
        return max(best, currentStreak)
    }

    private func hasClip(on day: Date) -> Bool {
        allClips.contains { cal.startOfDay(for: $0.createdAt) == day }
    }

    // MARK: - Lookback data

    private var lastWeekGroups: [(Date, [Clip])] {
        let start = cal.date(byAdding: .day, value: -7, to: today)!
        return grouped(from: start, to: today)
    }

    private var lastMonthGroups: [(Date, [Clip])] {
        let firstThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        let firstLastMonth = cal.date(byAdding: .month, value: -1, to: firstThisMonth)!
        return grouped(from: firstLastMonth, to: firstThisMonth)
    }

    private var lastYearGroups: [(Date, [Clip])] {
        let anchor = cal.date(byAdding: .year, value: -1, to: today)!
        let start  = cal.date(byAdding: .day, value: -7, to: anchor)!
        let end    = cal.date(byAdding: .day, value: 8,  to: anchor)!
        return grouped(from: start, to: end)
    }

    private func grouped(from start: Date, to end: Date) -> [(Date, [Clip])] {
        let matching = allClips
            .filter {
                let d = cal.startOfDay(for: $0.createdAt)
                return d >= start && d < end && !($0.project?.isDeleted ?? false)
            }
            .sorted { $0.createdAt < $1.createdAt }
        let byDay = Dictionary(grouping: matching) { cal.startOfDay(for: $0.createdAt) }
        return byDay.keys.sorted().map { ($0, byDay[$0]!) }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if allClips.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                            .padding(.horizontal, 20)
                        statsGrid
                            .padding(.horizontal, 20)
                        streakCard
                            .padding(.horizontal, 20)
                        if !lastWeekGroups.isEmpty {
                            lookbackSection("Last Week", groups: lastWeekGroups)
                        }
                        if !lastMonthGroups.isEmpty {
                            lookbackSection("Last Month", groups: lastMonthGroups)
                        }
                        if !lastYearGroups.isEmpty {
                            lookbackSection("Last Year", groups: lastYearGroups)
                        }
                        if lastWeekGroups.isEmpty && lastMonthGroups.isEmpty && lastYearGroups.isEmpty {
                            noLookbackHint
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 60)
                    .padding(.bottom, 120)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Memories")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Text(formattedToday)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 36, height: 36)
                    .background(Color(white: 0.12), in: Circle())
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var formattedToday: String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: Date())
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            statCard(value: "\(allClips.count)",  label: "Clips")
            statCard(value: "\(projects.count)",  label: "Projects")
            statCard(value: "\(recordingDays)",   label: "Recording Days")
            statCard(value: totalDurationLabel,   label: "Total Duration")
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.07), lineWidth: 1))
    }

    // MARK: - Streak card

    private var streakCard: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(currentStreak > 0 ? Theme.amber : .white.opacity(0.2))
                        Text("\(currentStreak)")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                    Text("Day Streak")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(bestStreak)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Best Streak")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            // Last 7 days dots
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { offset in
                    let day = cal.date(byAdding: .day, value: -(6 - offset), to: today)!
                    let active = hasClip(on: day)
                    let isToday = offset == 6
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(active ? Theme.amber : Color(white: 0.18))
                                .frame(width: 10, height: 10)
                            if isToday && !active {
                                Circle()
                                    .strokeBorder(Theme.amber.opacity(0.4), lineWidth: 1.5)
                                    .frame(width: 10, height: 10)
                            }
                        }
                        Text(shortDayLabel(for: day))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(active ? .white.opacity(0.65) : .white.opacity(0.2))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.07), lineWidth: 1))
    }

    private func shortDayLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EE"
        return String(f.string(from: date).prefix(2))
    }

    // MARK: - Lookback section

    private func lookbackSection(_ title: String, groups: [(Date, [Clip])]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .tracking(0.8)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(groups, id: \.0) { day, clips in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(dayLabel(for: day))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.35))
                            HStack(spacing: 6) {
                                ForEach(clips.prefix(4)) { clip in
                                    LookbackClipCell(clip: clip)
                                }
                                if clips.count > 4 {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(white: 0.15))
                                        Text("+\(clips.count - 4)")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                    .frame(width: 72, height: 96)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func dayLabel(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        if cal.isDateInToday(date)     { return String(localized: "Today") }
        if cal.isDateInYesterday(date) { return String(localized: "Yesterday") }
        f.dateFormat = "EEE, d. MMM"
        return f.string(from: date)
    }

    // MARK: - No lookback hint

    private var noLookbackHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Memories Appear Here")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            Text("Record a few more days — your first memories will appear here after a week.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.25))
                .lineSpacing(2)
        }
        .padding(16)
        .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 44))
                .foregroundStyle(Theme.amber.opacity(0.4))
            Text("No Recordings Yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Text("Record your first clip —\nyour memories will appear here soon.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - LookbackClipCell

private struct LookbackClipCell: View {
    let clip: Clip
    @State private var thumb: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.13))

            if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "film")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.18))
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
        .task { await loadThumb() }
    }

    private func loadThumb() async {
        if let data = clip.thumbnailData, let img = UIImage(data: data) {
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

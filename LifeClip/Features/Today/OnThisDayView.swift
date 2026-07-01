import SwiftUI
import SwiftData
import AVFoundation

struct OnThisDayView: View {
    @Query(filter: #Predicate<Clip> { !$0.isDeleted })
    private var allClips: [Clip]

    @Query(filter: #Predicate<Project> { !$0.isDeleted })
    private var projects: [Project]

    @State private var showSettings = false
    @State private var showStreakDetail = false
    @State private var viewerClips: [Clip]?
    @State private var viewerIndex: Int = 0

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
        .fullScreenCover(isPresented: Binding(
            get: { viewerClips != nil },
            set: { if !$0 { viewerClips = nil } }
        )) {
            if let clips = viewerClips {
                LookbackClipViewer(clips: clips, initialIndex: viewerIndex)
            }
        }
        .sheet(isPresented: $showStreakDetail) {
            StreakDetailView(
                recordingDays: Set(uniqueRecordingDays),
                currentStreak: currentStreak,
                bestStreak: bestStreak,
                totalRecordingDays: recordingDays,
                today: today,
                calendar: cal
            )
        }
    }

    private func openViewer(_ clips: [Clip], at index: Int) {
        viewerIndex = index
        viewerClips = clips
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.leading, 4)
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
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { showStreakDetail = true }
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
                                ForEach(Array(clips.prefix(4).enumerated()), id: \.element.id) { idx, clip in
                                    LookbackClipCell(clip: clip) { openViewer(clips, at: idx) }
                                }
                                if clips.count > 4 {
                                    Button { openViewer(clips, at: 4) } label: {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(white: 0.15))
                                            Text("+\(clips.count - 4)")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.5))
                                        }
                                        .frame(width: 72, height: 96)
                                    }
                                    .buttonStyle(.plain)
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

// MARK: - LookbackClipViewer

/// Fullscreen, swipeable viewer for a day's clips. Photos show their original
/// still image; videos play in an AVPlayer.
private struct LookbackClipViewer: View {
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
    }

    @ViewBuilder
    private func page(for clip: Clip, i: Int) -> some View {
        if clip.isPhoto {
            ZStack {
                Color.black
                if let img = photoImage(clip) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                }
            }
        } else {
            ZStack {
                Color.black
                if let player = players[clip.id] {
                    VideoLayerView(player: player)
                        .onTapGesture {
                            if player.timeControlStatus == .playing { player.pause() }
                            else { player.play() }
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

// MARK: - StreakDetailView

/// Scrollable, month-by-month calendar showing which days had recordings.
/// Mirrors the streak card's visual language: amber = recorded, grey = empty.
private struct StreakDetailView: View {
    let recordingDays: Set<Date>
    let currentStreak: Int
    let bestStreak: Int
    let totalRecordingDays: Int
    let today: Date
    let calendar: Calendar

    @Environment(\.dismiss) private var dismiss

    // Months from the current one back to the earliest recording, newest first.
    private var months: [Date] {
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let earliestDay = recordingDays.min() ?? today
        let earliestMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: earliestDay)) ?? currentMonth
        var result: [Date] = []
        var cursor = currentMonth
        var guardCount = 0
        while cursor >= earliestMonth && guardCount < 600 {
            result.append(cursor)
            cursor = calendar.date(byAdding: .month, value: -1, to: cursor) ?? earliestMonth
            guardCount += 1
        }
        return result
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    summaryCard
                    ForEach(months, id: \.self) { month in
                        StreakMonthGrid(
                            monthStart: month,
                            recordingDays: recordingDays,
                            today: today,
                            calendar: calendar
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .safeAreaInset(edge: .top) { topBar }
        .presentationBackground(.black)
    }

    private var topBar: some View {
        HStack {
            Text("Streak")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Color(white: 0.14), in: Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(Color.black)
    }

    private var summaryCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(currentStreak > 0 ? Theme.amber : .white.opacity(0.2))
                        Text("\(currentStreak)")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
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

            HStack(spacing: 14) {
                legendItem(color: Theme.amber, label: "Recorded")
                legendItem(color: Color(white: 0.18), label: "No clip")
                Spacer()
                Text("\(totalRecordingDays) days total")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(18)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.07), lineWidth: 1))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

// MARK: - StreakMonthGrid

/// A single month rendered as a 7-column calendar grid.
private struct StreakMonthGrid: View {
    let monthStart: Date
    let recordingDays: Set<Date>
    let today: Date
    let calendar: Calendar

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(monthTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, sym in
                    Text(sym)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.07), lineWidth: 1))
    }

    private func dayCell(_ day: Date) -> some View {
        let active = recordingDays.contains(calendar.startOfDay(for: day))
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let inFuture = day > today
        return ZStack {
            Circle()
                .fill(active ? Theme.amber : Color(white: inFuture ? 0.11 : 0.18))
            if isToday && !active {
                Circle().strokeBorder(Theme.amber.opacity(0.5), lineWidth: 1.5)
            }
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(active ? Theme.ink
                                 : inFuture ? .white.opacity(0.18) : .white.opacity(0.55))
        }
        .frame(height: 34)
    }

    // MARK: Layout helpers

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = calendar.locale ?? .current
        f.dateFormat = "MMMM yyyy"
        return f.string(from: monthStart)
    }

    // Weekday header symbols ordered to match the calendar's first weekday.
    private var weekdaySymbols: [String] {
        let f = DateFormatter()
        f.locale = calendar.locale ?? .current
        let symbols = f.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let start = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % 7] }
    }

    // Day cells with leading blanks so the 1st lands under the right weekday.
    private var cells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for d in range {
            result.append(calendar.date(byAdding: .day, value: d - 1, to: monthStart))
        }
        return result
    }
}

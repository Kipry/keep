import SwiftUI
import SwiftData
import AVFoundation

struct OnThisDayView: View {
    /// True while Memories is the visible page. `ContentView` keeps all three
    /// pages mounted, so `onAppear` fires at launch — the spiral's intro has to
    /// hang off this instead, or it plays to an empty room.
    let isActive: Bool

    @Query(filter: #Predicate<Clip> { !$0.isDeleted })
    private var storedClips: [Clip]

    @Query(filter: #Predicate<Project> { !$0.isDeleted })
    private var projects: [Project]

    /// Clips of trashed projects were still counted in every stat and in the
    /// streak, so the in-app numbers disagreed with the widget's — which has
    /// always filtered them (`WidgetDataStore.refresh`). Only `grouped(from:to:)`
    /// got this right before.
    private var allClips: [Clip] {
        storedClips.filter { !($0.project?.isDeleted ?? false) }
    }

    /// Everything derived from the clip list, computed once per change instead
    /// of per body evaluation.
    ///
    /// These were plain computed properties, which SwiftUI does not memoise.
    /// The body read each lookback group two or three times, `currentStreak`
    /// re-derived `uniqueRecordingDays`, `bestStreak` re-derived both, and the
    /// weekday row ran seven linear scans — roughly twenty full passes over
    /// every clip in the database per evaluation, on a view that
    /// `ContentView` keeps permanently mounted and therefore re-evaluates on
    /// any data change anywhere in the app.
    @State private var stats = MemoriesStats.empty
    /// Gapless day list backing the year spiral, rebuilt alongside the stats.
    @State private var spiralDays: [SpiralDay] = []

    @State private var showSettings = false
    @State private var showStreakDetail = false
    @State private var viewerClips: [Clip]?
    @State private var viewerIndex: Int = 0

    private var cal: Calendar { .current }
    private var today: Date { cal.startOfDay(for: Date()) }

    // Read-through accessors so the view body stays unchanged.
    private var recordingDays: Int { stats.recordingDays }
    private var totalDurationLabel: String { stats.totalDurationLabel }
    private var uniqueRecordingDays: [Date] { stats.uniqueDays }
    private var clipsByDay: [Date: [Clip]] { stats.clipsByDay }
    private var currentStreak: Int { stats.currentStreak }
    private var bestStreak: Int { stats.bestStreak }
    private var lastYearGroups: [(Date, [Clip])] { stats.lastYear }

    private func hasClip(on day: Date) -> Bool { stats.daySet.contains(day) }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Theme.background, not Color.black — pure black made this tab read
            // a shade darker than Library/Diary and showed as a band at the top.
            Theme.background.ignoresSafeArea()
            if allClips.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                            .padding(.horizontal, Layout.gutter)
                        statsGrid
                            .padding(.horizontal, Layout.gutter)
                        streakCard
                            .padding(.horizontal, Layout.gutter)
                        // Replaces the week/month lookback strips. Those showed
                        // the same days the Diary already shows, only smaller —
                        // and something from six days ago isn't a memory yet.
                        if !spiralDays.isEmpty {
                            YearSpiralCard(days: spiralDays,
                                           hasRecordedToday: hasClip(on: today),
                                           isActive: isActive) { day in
                                openDay(day)
                            }
                            .padding(.horizontal, Layout.gutter)
                        }
                        if !lastYearGroups.isEmpty {
                            lookbackSection("Last Year", groups: lastYearGroups)
                        }
                    }
                    .padding(.top, Layout.headerTop)
                    .padding(.bottom, 120)
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewerClips != nil },
            set: { if !$0 { viewerClips = nil } }
        )) {
            if let clips = viewerClips {
                ClipViewer(clips: clips, initialIndex: viewerIndex)
            }
        }
        .sheet(isPresented: $showStreakDetail) {
            StreakDetailView(
                clipsByDay: clipsByDay,
                recordingDays: Set(uniqueRecordingDays),
                currentStreak: currentStreak,
                bestStreak: bestStreak,
                totalRecordingDays: recordingDays,
                today: today,
                calendar: cal
            )
        }
        // Recomputed only when the clip set actually changes, not per frame.
        .onAppear { rebuildStats() }
        .onChange(of: storedClips) { _, _ in rebuildStats() }

    }

    private func rebuildStats() {
        stats = MemoriesStats.build(clips: allClips, calendar: cal)
        spiralDays = buildSpiralDays()
    }

    /// One entry per calendar day from the first recording to today — gaps
    /// included, because a gap holds its place on the disc.
    private func buildSpiralDays() -> [SpiralDay] {
        guard let first = stats.uniqueDays.last else { return [] }
        var result: [SpiralDay] = []
        var cursor = first
        // Guard against a clip dated in the future dragging the loop forever.
        while cursor <= today, result.count < 4000 {
            let clips = stats.clipsByDay[cursor] ?? []
            let components = cal.dateComponents([.year, .month], from: cursor)
            let seconds = Int(clips.reduce(0) { $0 + $1.effectiveDuration }.rounded())
            // Band share, driven by how many times you reached for the phone
            // that day rather than by seconds captured — clip count is the
            // signal that actually varies in a one-clip-a-day app, and it
            // reads unambiguously. One clip is a quarter shorter than a full
            // band and it saturates at four, against a fixed scale rather
            // than the busiest day: otherwise one unusual day would reshape
            // the whole disc. Empty days recess to a notch well below any of
            // them.
            let weight: CGFloat = clips.isEmpty
                ? 0.42
                : 0.75 + 0.25 * min(1, CGFloat(clips.count - 1) / 3)
            result.append(SpiralDay(
                id: cursor,
                tone: ClipTone.dayTone(clips),
                clipCount: clips.count,
                seconds: seconds,
                monthKey: (components.year ?? 0) * 12 + (components.month ?? 0),
                weight: weight
            ))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private func openDay(_ day: SpiralDay) {
        guard let clips = stats.clipsByDay[day.id], !clips.isEmpty else { return }
        openViewer(clips, at: 0)
    }

    private func openViewer(_ clips: [Clip], at index: Int) {
        viewerIndex = index
        viewerClips = clips
    }

    // MARK: - Header

    // Matches the DIARY / LIBRARY headers: mono eyebrow (here the date) above a
    // hand-lettered title, bottom-aligned with the trailing action button.
    private var header: some View {
        ScreenHeader(eyebrow: Text(headerDateLabel), title: Text("Chronicle")) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 36, height: 36)
                    .background(Theme.control, in: Circle())
            }
            .accessibilityLabel("Settings")
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var headerDateLabel: String {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "EEEE · d. MMMM"
        return f.string(from: Date()).uppercased()
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

    // `label` is a LocalizedStringKey and the uppercasing is done by the text
    // renderer, not by String.uppercased() — that ran before lookup and threw
    // the key away, so these four labels never translated.
    private func statCard(value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .textCase(.uppercase)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
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
                    let day = cal.date(byAdding: .day, value: -(6 - offset), to: today) ?? today
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
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
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

    private func lookbackSection(_ title: LocalizedStringKey, groups: [(Date, [Clip])]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .tracking(0.8)
                .padding(.horizontal, Layout.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(groups, id: \.0) { day, clips in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(dayLabel(for: day))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.35))
                            HStack(spacing: 6) {
                                ForEach(Array(clips.prefix(4).enumerated()), id: \.element.id) { idx, clip in
                                    ClipThumbCell(clip: clip) { openViewer(clips, at: idx) }
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
                .padding(.horizontal, Layout.gutter)
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

    // MARK: - Empty state

    /// Empty memories tab. Carries the same header as the populated screen —
    /// otherwise the tab looked like a different app when there's no data yet
    /// (and Settings, which lives in the header, became unreachable).
    private var emptyState: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Layout.gutter)
                .padding(.top, Layout.headerTop)

            Spacer()

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

            Spacer()
            Spacer()
        }
    }
}

// MARK: - StreakDetailView

/// Scrollable, month-by-month calendar showing which days had recordings.
/// Mirrors the streak card's visual language: amber = recorded, grey = empty.
/// The stats stay pinned at the top, opening lands on the current month, and
/// tapping a recorded day slides up a card with that day's clips.
private struct StreakDetailView: View {
    let clipsByDay: [Date: [Clip]]
    let recordingDays: Set<Date>
    let currentStreak: Int
    let bestStreak: Int
    let totalRecordingDays: Int
    let today: Date
    let calendar: Calendar

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay: Date?
    @State private var viewerClips: [Clip]?
    @State private var viewerIndex = 0

    // Months from the earliest recording up to the current one, oldest first.
    private var months: [Date] {
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let earliestDay = recordingDays.min() ?? today
        let earliestMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: earliestDay)) ?? currentMonth
        var result: [Date] = []
        var cursor = earliestMonth
        var guardCount = 0
        while cursor <= currentMonth && guardCount < 600 {
            result.append(cursor)
            cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? currentMonth
            guardCount += 1
        }
        return result
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            // The stats card sits outside the scroll view so it stays pinned
            // while the month grids scroll away underneath it.
            VStack(spacing: 0) {
                summaryCard
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            ForEach(months, id: \.self) { month in
                                StreakMonthGrid(
                                    monthStart: month,
                                    recordingDays: recordingDays,
                                    today: today,
                                    calendar: calendar,
                                    selectedDay: selectedDay,
                                    onSelectDay: select(day:)
                                )
                                .id(month)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        // Extra room while the day card is up so the last month
                        // can still be scrolled above it.
                        .padding(.bottom, selectedDay == nil ? 40 : 200)
                    }
                    // Months dissolve softly under the pinned stats card
                    // instead of being cut off at a hard edge.
                    .topEdgeFade()
                    // Land on the current month; scrolling up reveals the past.
                    .onAppear {
                        if let newest = months.last {
                            proxy.scrollTo(newest, anchor: .bottom)
                        }
                    }
                }
            }

            if let day = selectedDay, let clips = clipsByDay[day] {
                dayClipsCard(day: day, clips: clips)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: selectedDay)
        .sensoryFeedback(.selection, trigger: selectedDay)
        .safeAreaInset(edge: .top) { topBar }
        .presentationBackground(.black)
        .fullScreenCover(isPresented: Binding(
            get: { viewerClips != nil },
            set: { if !$0 { viewerClips = nil } }
        )) {
            if let clips = viewerClips {
                ClipViewer(clips: clips, initialIndex: viewerIndex)
            }
        }
    }

    private func select(day: Date) {
        selectedDay = selectedDay == day ? nil : day
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
                    .background(Theme.control, in: Circle())
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
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
    }

    private func legendItem(color: Color, label: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: Day clips card

    // Bottom card that slides up when a recorded day is tapped: weekday, date,
    // clip count, and the day's clips as tappable thumbnails.
    private func dayClipsCard(day: Date, clips: [Clip]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dayTitle(day))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(daySubtitle(day, count: clips.count))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.amber)
                }
                Spacer()
                Button { selectedDay = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 28, height: 28)
                        .background(Theme.control, in: Circle())
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { idx, clip in
                        ClipThumbCell(clip: clip) {
                            viewerIndex = idx
                            viewerClips = clips
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 20, y: 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func dayTitle(_ day: Date) -> String {
        if calendar.isDate(day, inSameDayAs: today) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(day, inSameDayAs: yesterday) { return String(localized: "Yesterday") }
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "EEEE"
        return f.string(from: day)
    }

    private func daySubtitle(_ day: Date, count: Int) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "d. MMMM yyyy"
        let date = f.string(from: day)
        return count == 1
            ? String(localized: "\(date) · 1 Clip")
            : String(localized: "\(date) · \(count) Clips")
    }
}

// MARK: - StreakMonthGrid

/// A single month rendered as a 7-column calendar grid.
private struct StreakMonthGrid: View {
    let monthStart: Date
    let recordingDays: Set<Date>
    let today: Date
    let calendar: Calendar
    let selectedDay: Date?
    let onSelectDay: (Date) -> Void

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
                ForEach(Array(cells.enumerated()), id: \.offset) { idx, day in
                    if let day {
                        dayCell(day, column: idx % 7)
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
    }

    // Streak band: pre-blended amber-over-card colour. An opaque fill lets the
    // per-cell half-bands overlap invisibly in the column gaps — translucent
    // stubs would show hairline seams at non-integral .flexible() widths.
    private static let bandColor = Color(red: 0.369, green: 0.237, blue: 0.141)

    private func dayCell(_ day: Date, column: Int) -> some View {
        let dayKey = calendar.startOfDay(for: day)
        let active = recordingDays.contains(dayKey)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let inFuture = day > today
        let isSelected = selectedDay == dayKey
        let prev = calendar.date(byAdding: .day, value: -1, to: dayKey)
        let next = calendar.date(byAdding: .day, value: 1, to: dayKey)
        let connectsLeft  = active && prev.map { recordingDays.contains(calendar.startOfDay(for: $0)) } == true
        let connectsRight = active && next.map { recordingDays.contains(calendar.startOfDay(for: $0)) } == true
        return ZStack {
            // Connector band behind the dot: consecutive recorded days read as
            // one continuous run. At row/month edges the half-band stops at the
            // cell edge as a stub, signalling the streak continues.
            if connectsLeft || connectsRight {
                HStack(spacing: 0) {
                    (connectsLeft  ? Self.bandColor : Color.clear).frame(maxWidth: .infinity)
                    (connectsRight ? Self.bandColor : Color.clear).frame(maxWidth: .infinity)
                }
                .frame(height: 26)
                .padding(.leading,  connectsLeft  && column > 0 ? -3.5 : 0)
                .padding(.trailing, connectsRight && column < 6 ? -3.5 : 0)
                .allowsHitTesting(false)
            }
            Circle()
                .fill(active ? Theme.amber : Color(white: inFuture ? 0.11 : 0.18))
                .shadow(color: isSelected ? Theme.amber.opacity(0.55) : .clear, radius: 7)
            if isToday && !active {
                Circle().strokeBorder(Theme.amber.opacity(0.5), lineWidth: 1.5)
            }
            if isSelected {
                Circle().strokeBorder(.white, lineWidth: 2)
            }
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(active ? Theme.ink
                                 : inFuture ? .white.opacity(0.18) : .white.opacity(0.55))
        }
        .frame(height: 34)
        .scaleEffect(isSelected ? 1.14 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.65), value: isSelected)
        .contentShape(Circle())
        .onTapGesture {
            guard active else { return }
            onSelectDay(dayKey)
        }
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

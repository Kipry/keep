import SwiftUI
import SwiftData
import UIKit
import AVFoundation
import ImageIO

// MARK: - Geometry / data model
//
// Internal coordinate is a *day index* ("tag"): day 0 == startDate, growing to
// `todayTag`. Everything (month scale, project bands, heatmap, film ruler) is
// laid out in this space and slid under a fixed centre playhead.

enum TimelineZoom: Int, CaseIterable {
    case day, week, month, year

    var pxPerDay: CGFloat {
        switch self {
        case .day:   return 24
        case .week:  return 11
        case .month: return 5
        case .year:  return 2.15
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .day:   return "Day"
        case .week:  return "Week"
        case .month: return "Month"
        case .year:  return "Year"
        }
    }
}

struct TimelineBand: Identifiable {
    let id: UUID
    let project: Project
    let name: String
    let startTag: Int
    let endTag: Int
    let clipCount: Int
    var lane: Int
    var center: Double { Double(startTag + endTag) / 2 }
    var span: Int { endTag - startTag + 1 }
}

struct TimelineData {
    let startDate: Date
    let total: Int
    let todayTag: Int
    let bands: [TimelineBand]
    let density: [Double]
    let maxDensity: Double
    let lanes: Int

    func date(at day: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: day, to: startDate) ?? startDate
    }

    static func build(projects: [Project], calendar: Calendar) -> TimelineData? {
        let active = projects.filter { !$0.isDeleted }
        guard !active.isEmpty else { return nil }

        let today = calendar.startOfDay(for: Date())

        // earliest recorded day across all clips (fall back to project creation)
        var earliest = today
        for p in active {
            let clips = p.activeClips
            if clips.isEmpty {
                earliest = min(earliest, calendar.startOfDay(for: p.createdAt))
            } else {
                for c in clips { earliest = min(earliest, calendar.startOfDay(for: c.createdAt)) }
            }
        }
        let startDate = min(earliest, today)
        let total = (calendar.dateComponents([.day], from: startDate, to: today).day ?? 0) + 1

        func tag(_ date: Date) -> Int {
            calendar.dateComponents([.day], from: startDate, to: calendar.startOfDay(for: date)).day ?? 0
        }

        var bands: [TimelineBand] = active.map { p in
            let clips = p.activeClips
            let dates = clips.isEmpty ? [p.createdAt] : clips.map(\.createdAt)
            let tags  = dates.map(tag)
            let s = tags.min() ?? 0
            let e = tags.max() ?? s
            return TimelineBand(id: p.id, project: p, name: p.name,
                                startTag: s, endTag: e, clipCount: clips.count, lane: 0)
        }
        bands.sort { $0.startTag < $1.startTag }

        // greedy lane assignment for time-overlapping bands (≤2 day gap = overlap)
        for i in bands.indices {
            var lane = 0
            var settled = false
            while !settled {
                settled = true
                for j in 0..<i where bands[j].lane == lane {
                    if bands[i].startTag <= bands[j].endTag + 2 && bands[i].endTag >= bands[j].startTag - 2 {
                        lane += 1; settled = false; break
                    }
                }
            }
            bands[i].lane = lane
        }
        let lanes = (bands.map(\.lane).max() ?? 0) + 1

        // per-day clip density (clips spread evenly across each project's days)
        var density = [Double](repeating: 0, count: max(total, 1))
        for b in bands {
            let len = max(b.endTag - b.startTag + 1, 1)
            let per = Double(b.clipCount) / Double(len)
            for d in b.startTag...b.endTag where d >= 0 && d < total { density[d] += per }
        }
        let maxD = max(density.max() ?? 1, 1)

        return TimelineData(startDate: startDate, total: total, todayTag: tag(today),
                            bands: bands, density: density, maxDensity: maxD, lanes: lanes)
    }
}

// MARK: - Month segments (shared by the timeline and the Places scrubber)

struct MonthSeg: Identifiable {
    let id = UUID()
    let date: Date
    let startTag: Int
    let days: Int
    let shortLabel: String  // "MMM" — pre-computed, no per-frame DateFormatter
    let fullLabel: String   // "MMMM"
    func label(short: Bool) -> String { short ? shortLabel : fullLabel }
}

extension TimelineData {
    /// Month boundaries across the timeline's day range with pre-formatted
    /// labels. Compute once per data rebuild and cache — the UUID identity of
    /// each segment is only stable within one computed array.
    func monthSegments(calendar: Calendar) -> [MonthSeg] {
        var segs: [MonthSeg] = []
        guard var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate)) else { return [] }
        let end = calendar.date(byAdding: .day, value: total, to: startDate) ?? startDate
        // Allocate formatters once for the whole loop, not once per segment.
        let shortFmt = DateFormatter(); shortFmt.locale = .current; shortFmt.dateFormat = "MMM"
        let fullFmt  = DateFormatter(); fullFmt.locale  = .current; fullFmt.dateFormat = "MMMM"
        var guardCount = 0
        while cursor < end && guardCount < 600 {
            let days = calendar.range(of: .day, in: .month, for: cursor)?.count ?? 30
            let startTag = calendar.dateComponents([.day], from: startDate, to: cursor).day ?? 0
            segs.append(MonthSeg(
                date: cursor, startTag: startTag, days: days,
                shortLabel: shortFmt.string(from: cursor).uppercased(),
                fullLabel:  fullFmt.string(from: cursor).uppercased()
            ))
            cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? end
            guardCount += 1
        }
        return segs
    }
}

// MARK: - Diary timeline screen

/// The diary's two faces: the scrubbable timeline and the places map.
private enum DiaryMode { case time, places }

struct DiaryTimelineView: View {
    /// False while another tab is showing (the pager keeps all pages mounted,
    /// so onDisappear never fires on tab switches — this drives autoplay stop).
    var isActive: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(filter: #Predicate<Project> { !$0.isDeleted })
    private var projects: [Project]

    @State private var data: TimelineData?
    @State private var centerDay: Double = 0
    @State private var zoom: TimelineZoom = .week
    @State private var isPlaying = false
    @State private var clipFrame = 0
    @State private var dragBase: Double?
    @State private var lastHapticDay = Int.min
    @State private var autoTask: Task<Void, Never>?
    @State private var selectedProject: Project?
    // Cached per-day results — recomputed only when focusedDay (Int) changes,
    // not on every animation frame while centerDay is animating.
    @State private var heroClips: [Clip] = []
    @State private var activeBand: TimelineBand?
    // Month segments change only when timeline data is rebuilt.
    @State private var cachedMonthSegs: [MonthSeg] = []
    // Places view: aggregated once per rebuild, like cachedMonthSegs.
    @State private var diaryMode: DiaryMode = .time
    @State private var placesData: PlacesData = .empty
    private let selectionFeedback = UISelectionFeedbackGenerator()

    private let calendar = Calendar.current

    // Static formatters — DateFormatter is expensive to allocate; reuse always.
    private static let _dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "dd.MM.yyyy"; return f
    }()
    private static let _weekdayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "EEEE"; return f
    }()
    private static let _monthYearFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "MMMM yyyy"; return f
    }()
    private static let _yearFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "yyyy"; return f
    }()

    private var px: CGFloat { zoom.pxPerDay }

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            ZStack(alignment: .top) {
                Theme.background.ignoresSafeArea()
                RadialGradient(colors: [Theme.amber.opacity(0.06), .clear],
                               center: .init(x: 0.5, y: 0.04), startRadius: 0, endRadius: 320)
                    .ignoresSafeArea()

                if let data, !data.bands.isEmpty {
                    content(width: geo.size.width, cx: cx, data: data)
                } else {
                    emptyScreen
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: rebuild)
        .onChange(of: projects.count) { _, _ in rebuild() }
        .onChange(of: focusedDay) { _, _ in refreshFocusedDay() }
        .onChange(of: isActive) { _, active in if !active { stopAutoplay() } }
        .onChange(of: diaryMode) { _, _ in stopAutoplay() }
        .onDisappear { stopAutoplay() }
        // Rebuild on return so clips added from the map's preview card show up.
        .fullScreenCover(item: $selectedProject, onDismiss: { rebuild() }) { project in
            ProjectDetailView(project: project, recordOnAppear: false)
        }
    }

    // MARK: Derived focus state

    private var focusedDay: Int {
        guard let data else { return 0 }
        return min(max(Int(centerDay.rounded()), 0), data.total - 1)
    }

    private var focusedDate: Date { data?.date(at: focusedDay) ?? Date() }

    private func clip(at offset: Int) -> Clip? {
        let c = heroClips
        guard !c.isEmpty else { return nil }
        let i = ((clipFrame + offset) % c.count + c.count) % c.count
        return c[i]
    }

    // MARK: - Content

    @ViewBuilder
    private func content(width: CGFloat, cx: CGFloat, data: TimelineData) -> some View {
        VStack(spacing: 0) {
            header(data: data)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            if diaryMode == .places {
                // Map twin of the diary — mounted only while visible so MapKit's
                // resources are freed when switching back to the timeline.
                PlacesMapView(
                    data: data,
                    places: placesData,
                    centerDay: $centerDay,
                    isActive: isActive && diaryMode == .places,
                    onOpenProject: { project in
                        stopAutoplay()
                        selectedProject = project
                    }
                )
            } else {
                // Preview: grows to fill all spare height so the timeline strip is
                // pinned to the bottom (near the tab bar) and a 9:16 clip shows tall.
                preview(data: data)
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08), lineWidth: 1))
                    // Hit region == the visible card. Defining contentShape AFTER
                    // the frame/clip keeps the preview's tap from bleeding up over
                    // the header (which was hijacking the Time/Places toggle).
                    .contentShape(RoundedRectangle(cornerRadius: 22))
                    .onTapGesture {
                        guard let band = activeBand else { return }
                        stopAutoplay()
                        selectedProject = band.project
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .layoutPriority(1)

                // Timeline strip pushed to the bottom
                controlRow(data: data)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                scrubber(width: width, cx: cx, data: data)
                    .padding(.top, 8)

                bigDate(data: data)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 10)
    }

    // MARK: Header

    private func header(data: TimelineData) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DIARY")
                    .font(.mono(10, weight: .medium))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.35))
                Text("Your Timeline")
                    .font(.hand(32))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()

            modePill

            // In places mode the map's own control row carries TODAY (it also
            // has to stop the flyover) — avoid a second, racing button here.
            if diaryMode == .time {
                Button {
                    stopAutoplay()
                    animateTo(Double(data.todayTag))
                } label: {
                    Text("TODAY")
                        .font(.mono(11))
                        .tracking(1)
                        .foregroundStyle(Theme.amber)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.amber.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(Theme.amber.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // "Zeit | Orte" switch — same pill language as the zoom selector.
    private var modePill: some View {
        HStack(spacing: 2) {
            modePillButton("Time", mode: .time)
            modePillButton("Places", mode: .places)
        }
        .padding(3)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }

    private func modePillButton(_ label: LocalizedStringKey, mode: DiaryMode) -> some View {
        let on = diaryMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { diaryMode = mode }
        } label: {
            Text(label)
                .font(.mono(11, weight: on ? .medium : .regular))
                .tracking(0.3)
                .foregroundStyle(on ? Theme.ink : .white.opacity(0.55))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(on ? Theme.amber : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: Preview window

    @ViewBuilder
    private func preview(data: TimelineData) -> some View {
        ZStack {
            Color(red: 0.078, green: 0.075, blue: 0.071)
            if !heroClips.isEmpty, let band = activeBand {
                previewActive(band)
            } else {
                previewEmpty(data: data)
            }
        }
        // Tap target is attached in content() AFTER the frame/clip, so the hit
        // region stays confined to the visible card (see below).
    }

    @ViewBuilder
    private func previewActive(_ band: TimelineBand) -> some View {
        ZStack {
            TimelineThumb(clip: clip(at: 0), fallback: band.startTag)
                .id(clip(at: 0)?.id ?? band.id)
                .transition(.opacity)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.4), location: 0),
                    .init(color: .clear, location: 0.26),
                    .init(color: .clear, location: 0.5),
                    .init(color: .black.opacity(0.88), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )

            VStack {
                // top badge + mini strip
                HStack(alignment: .top) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isPlaying ? Color.red : Theme.amber)
                            .frame(width: 7, height: 7)
                            .opacity(isPlaying ? blinkOpacity : 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isPlaying ? "LOOKBACK" : "PREVIEW")
                                .font(.mono(10))
                                .tracking(1.2)
                                .foregroundStyle(.white.opacity(0.85))
                            Text(verbatim: dateString(focusedDate))
                                .font(.mono(9))
                                .tracking(0.5)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(1...3, id: \.self) { k in
                            TimelineThumb(clip: clip(at: k), fallback: band.startTag + k)
                                .frame(width: 28, height: 38)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.25), lineWidth: 1))
                        }
                    }
                }
                .padding(.top, 13)
                .padding(.horizontal, 15)

                Spacer()

                // bottom: project name + chips
                VStack(alignment: .leading, spacing: 7) {
                    Text(band.name)
                        .font(.hand(29))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Text("\(heroClips.count) CLIPS")
                            .font(.mono(10.5))
                            .foregroundStyle(Theme.paper)
                            .padding(.horizontal, 9).padding(.vertical, 2)
                            .background(.black.opacity(0.5), in: Capsule())
                            .overlay(Capsule().stroke(Theme.paper.opacity(0.35), lineWidth: 1))
                        Text(relativeLabel(forDay: focusedDay))
                            .font(.mono(10.5))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 9).padding(.vertical, 2)
                            .background(Theme.amber, in: Capsule())
                        (band.span == 1 ? Text("single day") : Text("\(band.span) days"))
                            .font(.mono(10.5))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 17)
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private func previewEmpty(data: TimelineData) -> some View {
        ZStack {
            Color(red: 0.086, green: 0.078, blue: 0.071)
            VStack(spacing: 18) {
                TimelineLens(size: 64).opacity(0.4)
                VStack(spacing: 12) {
                    Text("No entry on this day")
                        .font(.hand(23))
                        .foregroundStyle(.white.opacity(0.62))
                    Text("\(Text(verbatim: dateString(focusedDate))) · \(relativeLabel(forDay: focusedDay))")
                        .font(.mono(11))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.3))
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
        .id("empty")
        .transition(.opacity)
    }

    // MARK: Control row

    private func controlRow(data: TimelineData) -> some View {
        HStack {
            HStack(spacing: 2) {
                ForEach(TimelineZoom.allCases, id: \.self) { z in
                    let on = z == zoom
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { zoom = z }  // centreDay preserved
                    } label: {
                        Text(z.label)
                            .font(.mono(11, weight: on ? .medium : .regular))
                            .tracking(0.3)
                            .foregroundStyle(on ? Theme.ink : .white.opacity(0.55))
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(on ? Theme.amber : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))

            Spacer()

            Button { togglePlay() } label: {
                ZStack {
                    Circle().fill(Theme.amber)
                        .frame(width: 42, height: 42)
                        .shadow(color: Theme.amber.opacity(0.4), radius: 9, y: 6)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Scrubber

    private func scrubber(width: CGFloat, cx: CGFloat, data: TimelineData) -> some View {
        let projH = CGFloat(data.lanes) * 20
        return ZStack(alignment: .top) {
            VStack(spacing: 6) {
                monthScale(cx: cx, data: data).frame(height: 22).clipped()
                projectBands(cx: cx, data: data).frame(height: projH)
                heatmap(cx: cx, data: data)
                    .frame(height: 12)
                    .mask(edgeFadeMask)
                filmRuler(cx: cx, data: data)
                    .frame(height: 30)
                    .mask(edgeFadeMask)
            }
            .overlay(alignment: .top) { playhead(projH: projH) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .contentShape(Rectangle())
        .gesture(dragGesture(data: data))
    }

    private var edgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.16),
                .init(color: .black, location: 0.84),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    // playhead line + triangle, fixed at centre
    private func playhead(projH: CGFloat) -> some View {
        let h = projH + 82   // monthScale(22)+bands+heat(12)+ruler(30) + 6pt gaps*3
        return ZStack(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Theme.amber.opacity(0), location: 0),
                    .init(color: Theme.amber, location: 0.14),
                    .init(color: Theme.amber, location: 0.92),
                    .init(color: Theme.amber.opacity(0), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 2, height: h)

            Triangle()
                .fill(Theme.amber)
                .frame(width: 12, height: 8)
                .offset(y: -2)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: Month scale

    @ViewBuilder
    private func monthScale(cx: CGFloat, data: TimelineData) -> some View {
        let segs = cachedMonthSegs
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(segs) { seg in
                let leftX = cx + CGFloat(Double(seg.startTag) - centerDay) * px
                let w = CGFloat(seg.days) * px
                let isActive = focusedDay >= seg.startTag && focusedDay < seg.startTag + seg.days
                let labelX = min(max(cx, leftX + 26), leftX + w - 26)

                // active highlight pill
                if isActive {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.amber.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.amber.opacity(0.45), lineWidth: 1))
                        .frame(width: max(w - 6, 0), height: 20)
                        .position(x: leftX + w / 2, y: 14)
                }
                // left divider
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 1, height: 28)
                    .position(x: leftX, y: 14)
                // label (sticky within visible segment)
                Text(seg.label(short: w <= 70))
                    .font(.mono(12, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(isActive ? Theme.amber : .white.opacity(0.5))
                    .fixedSize()
                    .position(x: labelX.isFinite ? labelX : leftX + w / 2, y: 14)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
    }

    // MARK: Project bands

    @ViewBuilder
    private func projectBands(cx: CGFloat, data: TimelineData) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(data.bands) { band in
                let leftX = cx + CGFloat(Double(band.startTag) - centerDay) * px
                let w = max(px * 1.2, CGFloat(band.span) * px)
                let on = activeBand?.id == band.id
                let showLabel = w >= 42
                let centerX = leftX + w / 2
                let y = CGFloat(band.lane) * 20 + 10

                Group {
                    if showLabel {
                        Text(band.name)
                            .font(.hand(13))
                            .foregroundStyle(on ? Theme.ink : Color(red: 0.863, green: 0.902, blue: 0.941))
                            .lineLimit(1)
                            .frame(width: w - 14, alignment: .leading)
                            .padding(.leading, 7)
                            .frame(width: w, height: 18, alignment: .leading)
                    } else {
                        Circle()
                            .fill(on ? Theme.ink : Color(red: 0.863, green: 0.902, blue: 0.941))
                            .frame(width: 5, height: 5)
                            .frame(width: w, height: 18)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(on ? Theme.amber : Color(red: 0.243, green: 0.361, blue: 0.463).opacity(0.92))
                        .overlay(on ? nil : RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.47, green: 0.59, blue: 0.71).opacity(0.35), lineWidth: 1))
                        .shadow(color: on ? Theme.amber.opacity(0.45) : .clear, radius: 7, y: 4)
                )
                .position(x: centerX, y: y)
                .onTapGesture {
                    stopAutoplay()
                    animateTo(band.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: Heatmap

    @ViewBuilder
    private func heatmap(cx: CGFloat, data: TimelineData) -> some View {
        let range = visibleRange(width: cx * 2, data: data)
        ZStack(alignment: .bottomLeading) {
            Color.clear
            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
            ForEach(range, id: \.self) { d in
                let v = data.density[d]
                if v > 0 {
                    let ratio = v / data.maxDensity
                    let barH = 2 + ratio * 10
                    Capsule()
                        .fill(Theme.amber.opacity(0.22 + 0.78 * ratio))
                        .frame(width: max(2, px - 1), height: barH)
                        .position(x: cx + CGFloat(Double(d) - centerDay) * px, y: 12 - barH / 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Film ruler

    @ViewBuilder
    private func filmRuler(cx: CGFloat, data: TimelineData) -> some View {
        let range = visibleRange(width: cx * 2, data: data)
        ZStack(alignment: .bottomLeading) {
            Color.clear
            ForEach(range, id: \.self) { d in
                if let tick = rulerTick(day: d, data: data) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(tick.color)
                        .frame(width: 2, height: tick.height)
                        .position(x: cx + CGFloat(Double(d) - centerDay) * px, y: 30 - tick.height / 2)
                }
            }
            // HEUTE marker
            let todayX = cx + CGFloat(Double(data.todayTag) - centerDay) * px
            DashedLine()
                .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                .frame(width: 2, height: 30)
                .position(x: todayX, y: 15)
            Text("TODAY")
                .font(.mono(8))
                .tracking(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                .fixedSize()
                .position(x: todayX, y: 3)
        }
        .frame(maxWidth: .infinity)
    }

    private struct Tick { let height: CGFloat; let color: Color }

    private func rulerTick(day d: Int, data: TimelineData) -> Tick? {
        let date = data.date(at: d)
        let isMonth = calendar.component(.day, from: date) == 1
        let isWeek  = calendar.component(.weekday, from: date) == 2   // Monday
        let isFocus = d == focusedDay
        if px < 4 && !isMonth && !isWeek && !isFocus { return nil }
        if px < 8 && !isMonth && !isWeek && !isFocus && d % 2 != 0 { return nil }
        let h: CGFloat = isMonth ? 22 : isWeek ? 14 : 8
        let color: Color = isFocus ? .white
            : isMonth ? Theme.amber
            : isWeek ? Theme.amber.opacity(0.85)
            : Theme.amber.opacity(0.4)
        return Tick(height: h, color: color)
    }

    // MARK: Big date

    private func bigDate(data: TimelineData) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: focusTitle(focusedDate))
                .font(.mono(30, weight: .medium))
                .tracking(2)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 16)
            Group {
                if let band = activeBand {
                    Text(verbatim: band.name).foregroundStyle(Theme.amber)
                } else {
                    Text(verbatim: focusSubtitle(focusedDate)).foregroundStyle(.white.opacity(0.4))
                }
            }
            .font(.hand(16))
        }
    }

    // Primary label adapts to the zoom level: exact date on Day, calendar week
    // on Week, month on Month, year on Year.
    private func focusTitle(_ date: Date) -> String {
        switch zoom {
        case .day:   return Self._dateFmt.string(from: date)
        case .week:
            let week = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.yearForWeekOfYear, from: date)
            return "KW \(week) · \(year)"
        case .month: return Self._monthYearFmt.string(from: date)
        case .year:  return Self._yearFmt.string(from: date)
        }
    }

    // Secondary line: weekday on Day zoom, otherwise the day's context.
    private func focusSubtitle(_ date: Date) -> String {
        zoom == .day ? weekdayString(date) : relativeLabel(forDay: focusedDay)
    }

    // MARK: Empty screen (no projects at all)

    private var emptyScreen: some View {
        VStack(spacing: 16) {
            TimelineLens(size: 72).opacity(0.5)
            Text("Your Timeline")
                .font(.hand(28))
                .foregroundStyle(.white)
            Text("Record your first clips — they'll line up here as a scrubbable diary.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
    }

    // MARK: - Helpers

    private func visibleRange(width: CGFloat, data: TimelineData) -> [Int] {
        let half = Double(width / 2 / px) + 2
        let lo = max(0, Int((centerDay - half).rounded(.down)))
        let hi = min(data.total - 1, Int((centerDay + half).rounded(.up)))
        guard lo <= hi else { return [] }
        return Array(lo...hi)
    }

    private func dateString(_ date: Date) -> String { Self._dateFmt.string(from: date) }
    private func weekdayString(_ date: Date) -> String { Self._weekdayFmt.string(from: date) }

    private var blinkOpacity: Double {
        // simple time-driven blink without extra timers
        Int(Date().timeIntervalSince1970 * 2) % 2 == 0 ? 1 : 0.2
    }

    private func relativeLabel(forDay day: Int) -> String {
        guard let data else { return "" }
        let d = data.todayTag - day
        switch d {
        case 0:  return String(localized: "today")
        case 1:  return String(localized: "yesterday")
        case -1: return String(localized: "tomorrow")
        default: break
        }
        if d > 1 && d < 7   { return String(localized: "\(d) days ago") }
        if d >= 7 && d < 14 { return String(localized: "1 week ago") }
        if d >= 14 && d < 56 { return String(localized: "\(Int((Double(d) / 7).rounded())) weeks ago") }
        if d >= 56 { return String(localized: "\(Int((Double(d) / 30).rounded())) months ago") }
        if d < -1 && d > -7 { return String(localized: "in \(-d) days") }
        return String(localized: "in \(Int((Double(-d) / 7).rounded())) weeks")
    }

    // MARK: - Interaction

    private func clampDay(_ v: Double) -> Double {
        guard let data else { return 0 }
        return max(0, min(Double(data.total - 1), v))
    }

    private func animateTo(_ day: Double) {
        let target = clampDay(day)
        if reduceMotion { centerDay = target }
        else { withAnimation(.easeOut(duration: 0.35)) { centerDay = target } }
    }

    private func dragGesture(data: TimelineData) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                if dragBase == nil {
                    dragBase = centerDay
                    stopAutoplay()
                    selectionFeedback.prepare()
                }
                let delta = -v.translation.width / px
                let nv = clampDay((dragBase ?? centerDay) + delta)
                let rounded = Int(nv.rounded())
                if rounded != lastHapticDay {
                    lastHapticDay = rounded
                    selectionFeedback.selectionChanged()
                }
                centerDay = nv
            }
            .onEnded { v in
                let c = centerDay
                dragBase = nil
                // Project forward using release velocity (flick momentum)
                let throwDays = -(v.velocity.width / px) * 0.13
                let thrown = clampDay(c + throwDays)
                // Snap to nearby project centre if landing close to one
                if let near = data.bands.min(by: { abs($0.center - thrown) < abs($1.center - thrown) }),
                   abs(near.center - thrown) <= 2.5 {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
                        centerDay = near.center
                    }
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
                        centerDay = thrown.rounded()
                    }
                }
            }
    }

    // MARK: - Auto-play "Lookback"

    private func togglePlay() {
        isPlaying ? stopAutoplay() : startAutoplay()
    }

    /// Sorted unique day-tags (0...todayTag) that actually contain clips.
    private func daysWithClips(in data: TimelineData) -> [Int] {
        var tags = Set<Int>()
        for band in data.bands {
            for clip in band.project.activeClips {
                let t = calendar.dateComponents([.day], from: data.startDate,
                                                to: calendar.startOfDay(for: clip.createdAt)).day ?? 0
                if (0...data.todayTag).contains(t) { tags.insert(t) }
            }
        }
        return tags.sorted()
    }

    // Walks chronologically through EVERY day that has clips, from the focused
    // day toward today, showing each of that day's clips exactly once, then
    // stops. Nothing is skipped: the old version only visited band centers and
    // dwelled a fixed 3 frames with a modulo counter, which repeated or dropped
    // clips whenever a day didn't have exactly three.
    private func startAutoplay() {
        guard let data else { return }
        let days = daysWithClips(in: data)
        guard !days.isEmpty else { return }   // bands can exist with zero clips
        isPlaying = true
        autoTask?.cancel()
        autoTask = Task { @MainActor in
            // Play forward from the focused day; if the user is already past the
            // last clip day (e.g. parked on an empty "today"), replay from the start.
            var queue = days.filter { $0 >= focusedDay }
            if queue.isEmpty { queue = days }

            for day in queue {
                guard !Task.isCancelled, isPlaying else { break }
                if Double(day) != centerDay {
                    let dist = abs(Double(day) - centerDay)
                    let dur = min(1.0, max(0.35, dist * 0.05))
                    if reduceMotion { centerDay = Double(day) }
                    else { withAnimation(.easeInOut(duration: dur)) { centerDay = Double(day) } }
                    try? await Task.sleep(nanoseconds: UInt64((dur + 0.1) * 1_000_000_000))
                }
                guard !Task.isCancelled, isPlaying else { break }
                for i in 0..<max(1, heroClips.count) {   // each clip exactly once
                    withAnimation(.easeInOut(duration: 0.25)) { clipFrame = i }
                    try? await Task.sleep(nanoseconds: 950_000_000)
                    guard !Task.isCancelled, isPlaying else { break }
                }
            }
            // Auto-stop once the lookback reaches the present.
            if !Task.isCancelled { isPlaying = false }
        }
    }

    private func stopAutoplay() {
        if isPlaying { isPlaying = false }
        autoTask?.cancel()
        autoTask = nil
    }

    // MARK: - Build

    private func rebuild() {
        let new = TimelineData.build(projects: projects, calendar: calendar)
        data = new
        if let new {
            // First build: open the diary on today, not on the latest project.
            if centerDay == 0 { centerDay = Double(new.todayTag) }
            centerDay = clampDay(centerDay)
            cachedMonthSegs = new.monthSegments(calendar: calendar)
            placesData = PlacesData.build(data: new, calendar: calendar)
        } else {
            placesData = .empty
        }
        refreshFocusedDay()
    }

    // Recompute the two most expensive derived values: which clips belong to
    // today and which band is active. Called only when focusedDay (Int) changes,
    // not on every animation frame while centerDay floats between day boundaries.
    private func refreshFocusedDay() {
        guard let data else { heroClips = []; activeBand = nil; clipFrame = 0; return }
        // Every day starts at its first clip — for manual scrubbing and autoplay.
        clipFrame = 0
        let day = focusedDay
        let date = data.date(at: day)
        let clips = data.bands.flatMap { band in
            band.project.activeClips.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
        }.sorted { $0.createdAt < $1.createdAt }
        heroClips = clips
        if let b = data.bands.first(where: { band in
            band.project.activeClips.contains { calendar.isDate($0.createdAt, inSameDayAs: date) }
        }) { activeBand = b }
        else { activeBand = data.bands.first { day >= $0.startTag && day <= $0.endTag } }
    }
}

// MARK: - Supporting views

/// Shows the stored low-res thumbnail immediately, then upgrades to a full-res
/// frame decoded from the actual video file for the hero preview.
private struct TimelineThumb: View {
    let clip: Clip?
    let fallback: Int
    @State private var thumbImage: UIImage?
    @State private var hiResImage: UIImage?

    var body: some View {
        ZStack {
            if let img = hiResImage ?? thumbImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: TimelinePalette.gradient(fallback),
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(
                        RadialGradient(colors: [.white.opacity(0.1), .clear],
                                       center: .init(x: 0.3, y: 0.1), startRadius: 0, endRadius: 120)
                    )
            }
        }
        .clipped()
        .task(id: clip?.id) { await load() }
    }

    private func load() async {
        thumbImage = nil
        hiResImage = nil
        guard let clip else { return }
        // Low-res thumbnail — show instantly from stored data
        if let data = clip.thumbnailData, let img = UIImage(data: data) {
            thumbImage = img
        }
        // Debounce: skip the expensive video decode if the user is still
        // scrolling past this clip. Only settle after 150 ms of stability.
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }

        // Photos: upgrade from the ORIGINAL still, not a frame of the rendered
        // .mov — the .mov can be stale or mis-oriented, whereas the source jpg
        // is always the exact image the user imported.
        if clip.isPhoto, let src = clip.photoSourceURL,
           let img = Self.downsampledImage(at: src, maxPixel: 1080) {
            hiResImage = img
            return
        }

        // Videos: upgrade to a full-res frame decoded from the video file
        let url = clip.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1080, height: 1080)
        guard let cgImg = try? await gen.image(at: .zero).image,
              !Task.isCancelled else { return }
        hiResImage = UIImage(cgImage: cgImg)
    }

    // Memory-efficient downscale straight from the file (ImageIO), preserving
    // aspect and applying EXIF orientation — avoids holding full-resolution
    // photos in memory while scrubbing.
    private static func downsampledImage(at url: URL, maxPixel: CGFloat) -> UIImage? {
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Minimal amber camera-lens mark (matches the keep. icon look).
private struct TimelineLens: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 0.984, green: 0.702, blue: 0.416),
                             Theme.amber,
                             Color(red: 0.788, green: 0.408, blue: 0.122)],
                    center: .init(x: 0.5, y: 0.3), startRadius: 0, endRadius: size * 0.55))
                .frame(width: size, height: size)
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.22), Color(white: 0.04)],
                                     center: .init(x: 0.36, y: 0.32), startRadius: 0, endRadius: size * 0.3))
                .frame(width: size * 0.42, height: size * 0.42)
            Circle().fill(Theme.amber).frame(width: size * 0.12, height: size * 0.12)
        }
    }
}

private enum TimelinePalette {
    static let grads: [[Color]] = [
        [Color(red: 0.231, green: 0.290, blue: 0.353), Color(red: 0.086, green: 0.114, blue: 0.153)],
        [Color(red: 0.353, green: 0.231, blue: 0.231), Color(red: 0.141, green: 0.082, blue: 0.086)],
        [Color(red: 0.278, green: 0.353, blue: 0.231), Color(red: 0.102, green: 0.141, blue: 0.082)],
        [Color(red: 0.290, green: 0.231, blue: 0.353), Color(red: 0.118, green: 0.082, blue: 0.153)],
        [Color(red: 0.353, green: 0.322, blue: 0.231), Color(red: 0.141, green: 0.122, blue: 0.082)],
        [Color(red: 0.231, green: 0.353, blue: 0.333), Color(red: 0.082, green: 0.141, blue: 0.129)],
        [Color(red: 0.322, green: 0.314, blue: 0.416), Color(red: 0.110, green: 0.106, blue: 0.153)],
        [Color(red: 0.416, green: 0.290, blue: 0.231), Color(red: 0.153, green: 0.102, blue: 0.082)]
    ]
    static func gradient(_ i: Int) -> [Color] { grads[((i % grads.count) + grads.count) % grads.count] }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

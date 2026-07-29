import SwiftUI
import UIKit

// MARK: - Arc

/// A ring segment in polar coordinates. Everything the spiral animates is an
/// interpolation between two of these — no path morphing anywhere.
struct Arc {
    var start: CGFloat      // radians
    var width: CGFloat      // arc width, radians
    var radius: CGFloat     // outer radius
    var band: CGFloat       // radial thickness

    func lerp(to target: Arc, _ u: CGFloat) -> Arc {
        // Normalise the target angle onto the nearest turn, otherwise a segment
        // three winds in spins the whole way round to reach the month dial.
        let wraps = ((start - target.start) / (2 * .pi)).rounded()
        let aligned = target.start + wraps * 2 * .pi
        return Arc(start:  start  + (aligned       - start)  * u,
                   width:  width  + (target.width  - width)  * u,
                   radius: radius + (target.radius - radius) * u,
                   band:   band   + (target.band   - band)   * u)
    }

    var path: Path {
        let inner = max(1, radius - band)
        let end = start + width
        var p = Path()
        p.addArc(center: .zero, radius: radius,
                 startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        p.addArc(center: .zero, radius: inner,
                 startAngle: .radians(end), endAngle: .radians(start), clockwise: true)
        p.closeSubpath()
        return p
    }
}

// MARK: - Geometry

/// The spiral grows **outward**: day one sits in the core, today is the
/// outermost and therefore widest segment.
///
/// That direction is the whole reason this works as a tappable control. Grown
/// inward, the most recent day — the one people reach for — would be the
/// smallest target and the past would own the area.
struct SpiralGeometry {
    /// May be fractional while the "new day" growth animation runs.
    var count: CGFloat
    var outerRadius: CGFloat = 150
    var maxTravel: CGFloat = 100

    /// Both clamps are the actual design decision. 0.55 at the bottom keeps
    /// twelve days a fat arc rather than a wisp of thread; 5.5 at the top holds
    /// the innermost band near 14 pt, below which the drawing turns to moiré.
    var turns: CGFloat { min(5.5, max(0.55, count / 72)) }
    var ringGap: CGFloat { min(28, maxTravel / turns) }
    var band: CGFloat { ringGap * 0.78 }
    var start: CGFloat { -.pi / 2 }
    var dTheta: CGFloat { count > 0 ? turns * 2 * .pi / count : 0 }
    var innerRadius: CGFloat { outerRadius - turns * ringGap }

    func angle(_ i: Int) -> CGFloat { start + CGFloat(i) * dTheta }

    /// Radius grows with the swept angle, so later days land further out.
    func radius(at angle: CGFloat) -> CGFloat {
        innerRadius + (angle - start) / (2 * .pi) * ringGap
    }

    func arc(_ i: Int) -> Arc {
        let a = angle(i)
        return Arc(start: a, width: dTheta * 0.94, radius: radius(at: a), band: band)
    }

    /// Tapping a single day only makes sense while a segment is wide enough to
    /// hit. The threshold follows from the geometry, never from the day count.
    var allowsDirectDayTap: Bool { outerRadius * dTheta >= 22 }

    /// Which day sits under a point. `tolerance` cushions thin winds.
    func index(at p: CGPoint, tolerance: CGFloat = 6) -> Int? {
        guard count > 0, dTheta > 0 else { return nil }
        let r = hypot(p.x, p.y)
        var phi = atan2(p.y, p.x)
        while phi < start { phi += 2 * .pi }
        for wrap in 0...Int(ceil(turns)) {
            let a = phi + CGFloat(wrap) * 2 * .pi
            let swept = a - start
            guard swept >= 0, swept <= turns * 2 * .pi else { continue }
            let rr = radius(at: a)
            if r <= rr + tolerance, r >= rr - band - tolerance {
                return min(Int(count) - 1, max(0, Int(swept / dTheta)))
            }
        }
        return nil
    }
}

/// Stage two: one month unrolled out of the spiral into a near-closed ring.
struct MonthDial {
    let dayCount: Int
    var radius: CGFloat = 150
    var band: CGFloat = 34
    var start: CGFloat { -.pi / 2 }
    /// Capped at 340° so the ring never closes into an ambiguous circle.
    var span: CGFloat { min(5.93, CGFloat(dayCount) * 0.30) }
    var step: CGFloat { dayCount > 0 ? span / CGFloat(dayCount) : 0 }

    func arc(_ k: Int) -> Arc {
        Arc(start: start + CGFloat(k) * step, width: step * 0.94,
            radius: radius, band: band)
    }

    func index(at p: CGPoint, tolerance: CGFloat = 6) -> Int? {
        guard dayCount > 0, step > 0 else { return nil }
        let r = hypot(p.x, p.y)
        guard r <= radius + tolerance, r >= radius - band - tolerance else { return nil }
        var rel = atan2(p.y, p.x) - start
        while rel < 0 { rel += 2 * .pi }
        guard rel <= span else { return nil }
        return min(dayCount - 1, Int(rel / step))
    }
}

// MARK: - Day model

/// One day on the disc. Gapless: days without a clip keep their place and are
/// drawn as bare paper, because a gap is part of the year too.
struct SpiralDay: Identifiable, Equatable {
    let id: Date            // start of day
    let tone: Color?        // nil = nothing recorded
    let clipCount: Int
    let seconds: Int
    let monthKey: Int       // year * 12 + month

    static func == (a: SpiralDay, b: SpiralDay) -> Bool {
        a.id == b.id && a.clipCount == b.clipCount && a.seconds == b.seconds
    }
}

// MARK: - Canvas

/// Every segment in a single `Canvas`. Deliberately not a `ForEach` of shapes:
/// 365 ring segments draw in well under a frame, 365 views do not.
struct SpiralCanvas: View, Animatable {
    let days: [SpiralDay]
    /// Global indices of the unrolled month, and their position within it.
    let monthOrder: [Int: Int]
    var reveal: CGFloat     // 0…1 intro
    var unroll: CGFloat     // 0…1 month dial
    var growth: CGFloat     // 0…1 "new day"
    var pulse: CGFloat      // 0…1 today's breath
    var selected: Int?

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { .init(reveal, .init(unroll, .init(growth, pulse))) }
        set {
            reveal = newValue.first
            unroll = newValue.second.first
            growth = newValue.second.second.first
            pulse  = newValue.second.second.second
        }
    }

    private var geometry: SpiralGeometry {
        .init(count: max(1, CGFloat(days.count) - 1 + growth))
    }
    private var dial: MonthDial { .init(dayCount: max(1, monthOrder.count)) }

    private static let plateFill = Color(red: 0.075, green: 0.071, blue: 0.067)   // #131211

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            let g = geometry
            let d = dial
            let head = reveal * CGFloat(days.count)

            // 1 · The dashed remainder of the current turn. The only place the
            //     spiral promises anything: this is where tomorrow goes.
            if reveal > 0.9, unroll < 1 {
                let from = g.start + g.turns * 2 * .pi
                let to = g.start + ceil(g.turns) * 2 * .pi
                if to - from > 0.05 {
                    var p = Path()
                    p.addArc(center: .zero, radius: g.outerRadius - g.band / 2,
                             startAngle: .radians(from), endAngle: .radians(to), clockwise: false)
                    ctx.stroke(p, with: .color(Theme.paper.opacity(0.09 * (1 - unroll))),
                               style: StrokeStyle(lineWidth: g.band, dash: [2, 5]))
                }
            }

            // 2 · Plate behind the unrolled month.
            if unroll > 0.01 {
                let platePath = Arc(start: d.start - 0.06, width: d.span + 0.12,
                                    radius: d.radius + 3, band: d.band + 6).path
                ctx.fill(platePath, with: .color(Self.plateFill.opacity(unroll)))
                ctx.stroke(platePath, with: .color(.white.opacity(0.07 * unroll)), lineWidth: 1)
            }

            // 3 · The days. Month members drawn last so they sit on top.
            for i in drawOrder {
                let day = days[i]
                let local = min(1, max(0, (head - CGFloat(i)) / 1.5))
                if local <= 0 { continue }

                var arc = g.arc(i)
                var alpha = local
                if let k = monthOrder[i] {
                    // 35 % stagger across the month — this is what makes it
                    // read as unrolling rather than snapping into place.
                    let f = CGFloat(k) / CGFloat(max(1, monthOrder.count))
                    let u = min(1, max(0, unroll * 1.35 - f * 0.35))
                    arc = arc.lerp(to: d.arc(k), u)
                } else {
                    alpha *= 1 - 0.74 * unroll          // core sinks to 26 %
                }
                if let s = selected, s != i { alpha *= 0.30 }
                if selected == i { arc.radius += 5 }
                arc.radius -= (1 - local) * 7           // intro: slides out into place

                ctx.fill(arc.path,
                         with: .color(day.tone?.opacity(alpha)
                                      ?? Theme.paper.opacity(0.06 * alpha)))
            }

            // 4 · Selection outline.
            if let s = selected, s < days.count {
                var arc = g.arc(s)
                if let k = monthOrder[s] { arc = arc.lerp(to: d.arc(k), unroll) }
                arc.radius += 5
                ctx.stroke(arc.path, with: .color(Theme.amber), lineWidth: 1.5)
            }

            // 5 · Today's breath — an outline on today's own empty segment.
            if pulse > 0, let last = days.indices.last {
                let arc = g.arc(last)
                ctx.stroke(arc.path,
                           with: .color(Theme.amber.opacity(0.15 + 0.5 * pulse)),
                           lineWidth: 1.5)
            }

            // 6 · The amber head running ahead of the thread.
            if reveal > 0, reveal < 1 {
                let a = g.start + head * g.dTheta
                let r = g.radius(at: a) - g.band / 2
                ctx.fill(Path(ellipseIn: CGRect(x: r * cos(a) - 3.2, y: r * sin(a) - 3.2,
                                                width: 6.4, height: 6.4)),
                         with: .color(Theme.amber.opacity(min(1, (1 - reveal) * 6))))
            }
        }
    }

    /// Non-month days first, month days last, each group in natural order.
    /// A comparator that only inspects one side is not a strict weak ordering
    /// and can trap inside `sorted`.
    private var drawOrder: [Int] {
        guard !monthOrder.isEmpty else { return Array(days.indices) }
        var base: [Int] = [], top: [Int] = []
        for i in days.indices {
            if monthOrder[i] != nil { top.append(i) } else { base.append(i) }
        }
        return base + top
    }
}

// MARK: - Card

/// The year spiral as it sits on the Memories page.
struct YearSpiralCard: View {
    let days: [SpiralDay]
    let hasRecordedToday: Bool
    /// True while the Memories tab is the visible page — the intro is bound to
    /// this, not to `onAppear`, because the page stays mounted from launch.
    let isActive: Bool
    var onOpenDay: (SpiralDay) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var reveal: CGFloat = 0
    @State private var unroll: CGFloat = 0
    @State private var growth: CGFloat = 1
    @State private var pulse: CGFloat = 0
    @State private var selected: Int?
    @State private var monthOrder: [Int: Int] = [:]
    @State private var monthLabel: String?
    @State private var didReveal = false
    @State private var knownDayCount = 0

    private let side: CGFloat = 314
    private var geometry: SpiralGeometry { .init(count: max(1, CGFloat(days.count))) }

    private var recordedDays: Int { days.reduce(0) { $0 + ($1.tone == nil ? 0 : 1) } }
    private var selectedDay: SpiralDay? {
        guard let selected, days.indices.contains(selected) else { return nil }
        return days[selected]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ZStack {
                SpiralCanvas(days: days, monthOrder: monthOrder, reveal: reveal,
                             unroll: unroll, growth: growth, pulse: pulse, selected: selected)
                    .frame(width: side, height: side)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 1, coordinateSpace: .local) { handleTap($0) }
                centreLabel
            }
            .frame(maxWidth: .infinity)
            legend
            if let day = selectedDay { dayCard(day) }
        }
        .padding(14)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Year spiral, \(recordedDays) of \(days.count) days recorded"))
        .onChange(of: isActive) { _, active in if active { startIfNeeded() } }
        .onAppear { if isActive { startIfNeeded() } }
        .onChange(of: days.count) { old, new in
            guard didReveal, new == old + 1 else { knownDayCount = new; return }
            knownDayCount = new
            growNewDay()
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            Text("Your Year")
                .font(.hand(19))
                .foregroundStyle(.white)
            Spacer()
            Text(verbatim: yearLabel)
                .font(.mono(9, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    private var yearLabel: String {
        guard let last = days.last?.id else { return "" }
        return String(Calendar.current.component(.year, from: last))
    }

    private var centreLabel: some View {
        VStack(spacing: 3) {
            Text(verbatim: monthLabel ?? yearLabel)
                .font(.hand(26))
                .foregroundStyle(Theme.paper)
            (monthLabel == nil
             ? Text("\(recordedDays) DAYS")
             : Text("TAP TO CLOSE"))
                .font(.mono(9))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.32))
        }
        .opacity(Double(min(1, max(0, (reveal - 0.78) / 0.22))))
        .allowsHitTesting(false)
    }

    private var legend: some View {
        HStack {
            Text("CENTRE: START")
            Spacer()
            Text("OUTSIDE: TODAY")
        }
        .font(.mono(8.5))
        .tracking(1)
        .foregroundStyle(.white.opacity(0.3))
    }

    private func dayCard(_ day: SpiralDay) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(day.tone ?? Color(white: 0.13))
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: day.id.formatted(date: .numeric, time: .omitted))
                    .font(.mono(12, weight: .medium))
                    .foregroundStyle(.white)
                Group {
                    if day.clipCount == 0 {
                        Text("NO RECORDING")
                    } else {
                        Text("\(day.clipCount) CLIPS · \(day.seconds) S")
                    }
                }
                .font(.mono(9))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.3))
            }
            Spacer(minLength: 4)
            if day.clipCount > 0 {
                Button { onOpenDay(day) } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 34, height: 34)
                        .background(Theme.amber, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open day")
            }
        }
        .padding(12)
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 13))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: Motion

    private func startIfNeeded() {
        guard !didReveal else { return }
        didReveal = true
        knownDayCount = days.count
        guard !reduceMotion else {
            reveal = 1
            if !hasRecordedToday { pulse = 0.45 }
            return
        }
        withAnimation(.timingCurve(0.16, 0.84, 0.3, 1, duration: 1.1)) { reveal = 1 }
        if !hasRecordedToday { schedulePulse() }
    }

    /// Three breaths, then quiet. No permanent pulse, no badge, no red.
    private func schedulePulse() {
        for n in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(n) * 1.4) {
                withAnimation(.easeInOut(duration: 0.7)) { pulse = 1 }
                withAnimation(.easeInOut(duration: 0.7).delay(0.7)) { pulse = 0 }
            }
        }
    }

    /// The reward: the rim grows. Turn count and band width both follow from the
    /// day count, so this is the same formula with `count + 1` — not a special case.
    private func growNewDay() {
        guard !reduceMotion else { return }
        growth = 0
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { growth = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.easeInOut(duration: 0.7)) { pulse = 1 }
            withAnimation(.easeInOut(duration: 0.7).delay(0.7)) { pulse = 0 }
        }
    }

    // MARK: Taps

    private func handleTap(_ location: CGPoint) {
        let p = CGPoint(x: location.x - side / 2, y: location.y - side / 2)

        // Stage two: inside the unrolled month pick a day, anywhere else roll up.
        if !monthOrder.isEmpty {
            let dial = MonthDial(dayCount: monthOrder.count)
            if let k = dial.index(at: p), let i = monthOrder.first(where: { $0.value == k })?.key {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.easeOut(duration: 0.22)) { selected = (selected == i) ? nil : i }
            } else {
                withAnimation(.timingCurve(0.16, 0.84, 0.3, 1, duration: 0.38)) {
                    unroll = 0
                    selected = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                    monthOrder = [:]
                    monthLabel = nil
                }
            }
            return
        }

        // Stage one: the spiral itself.
        guard let i = geometry.index(at: p), days.indices.contains(i) else {
            withAnimation(.easeOut(duration: 0.18)) { selected = nil }
            return
        }
        UISelectionFeedbackGenerator().selectionChanged()

        if geometry.allowsDirectDayTap {
            withAnimation(.easeOut(duration: 0.22)) { selected = (selected == i) ? nil : i }
        } else {
            openMonth(around: i)
        }
    }

    private func openMonth(around i: Int) {
        let key = days[i].monthKey
        let members = days.indices.filter { days[$0].monthKey == key }
        guard !members.isEmpty else { return }
        var order: [Int: Int] = [:]
        for (k, index) in members.enumerated() { order[index] = k }
        monthOrder = order
        monthLabel = days[i].id.formatted(.dateTime.month(.wide))
        selected = nil
        unroll = 0
        withAnimation(reduceMotion ? nil : .timingCurve(0.16, 0.84, 0.3, 1, duration: 0.56)) {
            unroll = 1
        }
    }
}

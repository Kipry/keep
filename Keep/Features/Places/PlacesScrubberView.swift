import SwiftUI
import UIKit

// MARK: - Compact time scrubber for the Places map

/// A 118pt condensed variant of the diary timeline: month scale, project dots,
/// TODAY marker and a fixed centered playhead, with the focused date below.
/// Uses the same geometry as the timeline — x = cx + (tag − centerDay) · px —
/// and snaps releases to days that actually have places.
struct PlacesScrubberView: View {
    let data: TimelineData
    let daysWithPlaces: [Int]
    @Binding var centerDay: Double
    let onScrubStart: () -> Void

    @State private var dragBase: Double?
    @State private var lastHapticDay = Int.min
    @State private var monthSegs: [MonthSeg] = []
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let calendar = Calendar.current

    /// Week-zoom density — the map scrubber has no zoom control.
    private let px: CGFloat = TimelineZoom.week.pxPerDay

    private static let _dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "dd.MM.yyyy"; return f
    }()
    private static let _weekdayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "EEEE"; return f
    }()

    private var focusedDay: Int {
        min(max(Int(centerDay.rounded()), 0), data.total - 1)
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let cx = geo.size.width / 2
                VStack(spacing: 6) {
                    monthScale(cx: cx).frame(height: 22).clipped()
                    projectDots(cx: cx).frame(height: 14)
                    ruler(cx: cx)
                        .frame(height: 30)
                        .mask(edgeFadeMask)
                }
                .overlay(alignment: .top) { playhead }
                .contentShape(Rectangle())
                .gesture(dragGesture)
            }
            .frame(height: 78)

            bigDate
        }
        .onAppear { monthSegs = data.monthSegments(calendar: calendar) }
        .onChange(of: data.total) { _, _ in monthSegs = data.monthSegments(calendar: calendar) }
    }

    // MARK: Month scale (condensed timeline variant)

    private func monthScale(cx: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(monthSegs) { seg in
                let leftX = cx + CGFloat(Double(seg.startTag) - centerDay) * px
                let w = CGFloat(seg.days) * px
                let isActive = focusedDay >= seg.startTag && focusedDay < seg.startTag + seg.days
                let labelX = min(max(cx, leftX + 26), leftX + w - 26)

                if isActive {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.amber.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.amber.opacity(0.45), lineWidth: 1))
                        .frame(width: max(w - 6, 0), height: 20)
                        .position(x: leftX + w / 2, y: 11)
                }
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 1, height: 22)
                    .position(x: leftX, y: 11)
                Text(seg.label(short: w <= 70))
                    .font(.mono(11, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(isActive ? Theme.amber : .white.opacity(0.5))
                    .fixedSize()
                    .position(x: labelX.isFinite ? labelX : leftX + w / 2, y: 11)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
    }

    // MARK: Project dots

    private func projectDots(cx: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(data.bands) { band in
                let x = cx + CGFloat(band.center - centerDay) * px
                let revealed = band.startTag <= focusedDay
                Circle()
                    .fill(revealed ? Theme.amber : .white.opacity(0.22))
                    .frame(width: 6, height: 6)
                    .position(x: x, y: 7)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: Ruler with place ticks + TODAY marker

    private func ruler(cx: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            // Ticks only where places were first visited — the scrubber's
            // meaningful stops.
            ForEach(daysWithPlaces, id: \.self) { d in
                let isFocus = d == focusedDay
                RoundedRectangle(cornerRadius: 1)
                    .fill(isFocus ? .white : Theme.amber.opacity(d <= focusedDay ? 0.9 : 0.35))
                    .frame(width: 2, height: isFocus ? 18 : 12)
                    .position(x: cx + CGFloat(Double(d) - centerDay) * px,
                              y: 30 - (isFocus ? 9 : 6))
            }
            let todayX = cx + CGFloat(Double(data.todayTag) - centerDay) * px
            PlacesDashedLine()
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

    private var playhead: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Theme.amber.opacity(0), location: 0),
                    .init(color: Theme.amber, location: 0.14),
                    .init(color: Theme.amber, location: 0.92),
                    .init(color: Theme.amber.opacity(0), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 2, height: 78)

            PlacesTriangle()
                .fill(Theme.amber)
                .frame(width: 12, height: 8)
                .offset(y: -2)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: Big date

    private var bigDate: some View {
        VStack(spacing: 1) {
            Text(verbatim: Self._dateFmt.string(from: data.date(at: focusedDay)))
                .font(.mono(24, weight: .medium))
                .tracking(2)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(verbatim: Self._weekdayFmt.string(from: data.date(at: focusedDay)))
                .font(.hand(14))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Drag with snap-to-place

    private func clampDay(_ v: Double) -> Double {
        max(0, min(Double(data.total - 1), v))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                if dragBase == nil {
                    dragBase = centerDay
                    onScrubStart()
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
                // Flick momentum, then snap to a nearby place day if one is close.
                let throwDays = -(v.velocity.width / px) * 0.13
                let thrown = clampDay(c + throwDays)
                let target: Double
                if let near = daysWithPlaces.min(by: { abs(Double($0) - thrown) < abs(Double($1) - thrown) }),
                   abs(Double(near) - thrown) <= 2.5 {
                    target = Double(near)
                } else {
                    target = thrown.rounded()
                }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) {
                    centerDay = target
                }
            }
    }
}

// MARK: - Shapes (private copies — the timeline's are file-private)

private struct PlacesTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

private struct PlacesDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

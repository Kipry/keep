import MapKit
import SwiftUI

// MARK: - Places map (the "Orte" diary view)

/// Map twin of the diary timeline: memories as thumbnail pins, a dashed
/// chronological travel route, a compact time scrubber, and a play flyover.
/// Shares `centerDay` with the timeline so switching views keeps the focus day.
struct PlacesMapView: View {
    let data: TimelineData
    let places: PlacesData
    @Binding var centerDay: Double
    let isActive: Bool
    let onOpenProject: (Project) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var camera: MapCameraPosition = .automatic
    @State private var follow = true
    @State private var routeVisible = true
    @State private var visibleRect = MKMapRect.world
    @State private var viewWidth: CGFloat = 0
    @State private var isPlaying = false
    @State private var flyTask: Task<Void, Never>?
    @State private var slideThumb: UIImage?

    private let calendar = Calendar.current

    // MARK: Derived state

    private var focusedDay: Int {
        min(max(Int(centerDay.rounded()), 0), data.total - 1)
    }

    /// Places revealed by the scrubber (first visited on or before the focused day).
    private var revealedPlaces: [Place] {
        places.places.filter { $0.firstDayTag <= focusedDay }
    }

    /// The place the camera follows: the most recently visited revealed one.
    private var activePlace: Place? { revealedPlaces.last }

    private var mapItems: [MapItem] {
        PlacesData.clusters(for: revealedPlaces, visibleRect: visibleRect, viewWidth: viewWidth)
    }

    private var revealedRoute: [CLLocationCoordinate2D] {
        let segmentCount = max(0, revealedPlaces.count - 1)
        return places.routeSegments.prefix(segmentCount).flatMap { $0 }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            mapArea
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08), lineWidth: 1))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .layoutPriority(1)

            controlRow
                .padding(.horizontal, 24)
                .padding(.top, 10)

            PlacesScrubberView(
                data: data,
                daysWithPlaces: places.daysWithPlaces,
                centerDay: $centerDay,
                onScrubStart: { stopFlyover() }
            )
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .onChange(of: centerDay) { _, _ in
            // Scrub, play and TODAY are the only writers of centerDay —
            // any of them re-engages the follow camera.
            follow = true
        }
        .onChange(of: activePlace?.id) { _, _ in
            guard follow, let place = activePlace else { return }
            fly(to: place)
        }
        .onChange(of: camera.positionedByUser) { _, byUser in
            // Manual pan/zoom/rotate: stop following and cancel the flyover.
            if byUser { follow = false; stopFlyover() }
        }
        .onChange(of: isActive) { _, active in
            if !active { stopFlyover() }
        }
        .onDisappear { stopFlyover() }
    }

    // MARK: Map

    private var mapArea: some View {
        GeometryReader { geo in
            ZStack {
                Map(position: $camera) {
                    if routeVisible && revealedRoute.count > 1 {
                        MapPolyline(coordinates: revealedRoute)
                            .stroke(Theme.amber, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 6]))
                    }
                    ForEach(mapItems) { item in
                        Annotation("", coordinate: item.coordinate, anchor: .center) {
                            annotationView(for: item)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .onMapCameraChange(frequency: .onEnd) { ctx in
                    visibleRect = ctx.rect   // clustering input only
                }

                if places.places.isEmpty { emptyOverlay }
            }
            .overlay(alignment: .bottom) {
                if let place = activePlace { previewCard(for: place) }
            }
            .onAppear { viewWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, w in viewWidth = w }
        }
    }

    @ViewBuilder
    private func annotationView(for item: MapItem) -> some View {
        switch item {
        case .place(let place):
            let isActivePin = place.id == activePlace?.id
            Button {
                stopFlyover()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    centerDay = Double(place.firstDayTag)
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let thumb = place.thumb {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Rectangle()
                                .fill(Theme.filmCard)
                                .overlay {
                                    Image(systemName: "film")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                        }
                    }
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isActivePin ? Theme.amber : Theme.paper, lineWidth: 3)
                    )
                    .shadow(color: isActivePin ? Theme.amber.opacity(0.6) : .black.opacity(0.4),
                            radius: isActivePin ? 8 : 4, y: 2)

                    if place.clipCount > 1 {
                        Text("\(place.clipCount)")
                            .font(.mono(10, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.amber, in: Capsule())
                            .offset(x: 8, y: -8)
                    }
                }
            }
            .buttonStyle(.plain)

        case .cluster(_, _, let members):
            Button {
                // Zoom toward the cluster; the smaller span resolves it.
                let cam = MapCamera(centerCoordinate: item.coordinate, distance: clusterZoomDistance())
                if reduceMotion { camera = .camera(cam) }
                else { withAnimation(.easeInOut(duration: 0.5)) { camera = .camera(cam) } }
            } label: {
                Text("\(members.reduce(0) { $0 + $1.clipCount })")
                    .font(.mono(11, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 30, height: 30)
                    .background(Theme.amber, in: Circle())
                    .overlay(Circle().stroke(Theme.paper.opacity(0.6), lineWidth: 2))
                    .shadow(color: Theme.amber.opacity(0.45), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Preview card

    private func previewCard(for place: Place) -> some View {
        Button {
            if let project = place.project {
                stopFlyover()
                onOpenProject(project)
            }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let img = (isPlaying ? slideThumb : nil) ?? place.thumb {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(Theme.filmCard)
                    }
                }
                .frame(width: 52, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.paper.opacity(0.5), lineWidth: 1.5))

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.project?.name ?? "—")
                        .font(.hand(20))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(verbatim: cardSubtitle(for: place))
                        .font(.mono(9.5))
                        .tracking(0.8)
                        .foregroundStyle(Theme.amber)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .buttonStyle(.plain)
    }

    private func cardSubtitle(for place: Place) -> String {
        let name = (place.displayName ?? String(localized: "Unknown place")).uppercased()
        let clips = place.clipCount == 1
            ? String(localized: "1 CLIP")
            : String(localized: "\(place.clipCount) CLIPS")
        return "\(name) · \(clips) · \(relativeLabel(forDay: place.firstDayTag))"
    }

    // MARK: Controls

    private var controlRow: some View {
        HStack(spacing: 10) {
            // Route on/off
            Button { routeVisible.toggle() } label: {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(routeVisible ? Theme.ink : .white.opacity(0.55))
                    .frame(width: 36, height: 36)
                    .background(routeVisible ? Theme.amber : .white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            // TODAY — jumps the scrubber (and re-engages follow)
            Button {
                stopFlyover()
                withAnimation(.easeOut(duration: 0.35)) { centerDay = Double(data.todayTag) }
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

            // Play — chronological flyover
            Button { isPlaying ? stopFlyover() : startFlyover() } label: {
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

    // MARK: Empty state

    private var emptyOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.25))
            Text("No places yet")
                .font(.hand(22))
                .foregroundStyle(.white.opacity(0.7))
            Text("New clips remember where they were captured — enable location in Settings.")
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(24)
    }

    // MARK: Camera

    private func fly(to place: Place) {
        let cam = MapCamera(centerCoordinate: place.coordinate, distance: 1400)
        if reduceMotion {
            camera = .camera(cam)
        } else {
            withAnimation(.easeInOut(duration: flyDuration(to: place))) { camera = .camera(cam) }
        }
    }

    private func flyDuration(to place: Place) -> Double {
        let from = visibleRect.origin.coordinate
        let meters = MKMapPoint(from).distance(to: MKMapPoint(place.coordinate))
        return min(1.2, max(0.4, meters / 80_000))
    }

    private func clusterZoomDistance() -> Double {
        // Halve the current viewport height as a simple "zoom in one step".
        let metersPerMapPoint = MKMetersPerMapPointAtLatitude(visibleRect.origin.coordinate.latitude)
        let currentMeters = visibleRect.size.height * metersPerMapPoint
        return max(600, currentMeters * 0.35)
    }

    // MARK: Flyover

    private func startFlyover() {
        guard !places.places.isEmpty else { return }
        isPlaying = true
        flyTask?.cancel()
        flyTask = Task { @MainActor in
            // From the focused day forward; if already past everything, replay.
            var queue = places.places.filter { $0.firstDayTag >= focusedDay }
            if queue.isEmpty { queue = places.places }

            for place in queue {
                guard !Task.isCancelled, isPlaying else { break }
                withAnimation(.easeInOut(duration: 0.25)) {
                    centerDay = Double(place.firstDayTag)   // reveals + follow flies
                }
                let travel = reduceMotion ? 0.1 : flyDuration(to: place)
                try? await Task.sleep(nanoseconds: UInt64((travel + 0.15) * 1_000_000_000))
                guard !Task.isCancelled, isPlaying else { break }

                // ~1.5s dwell, cycling through up to 4 of the place's thumbnails.
                let frames = max(1, min(place.clips.count, 4))
                let step = 1.5 / Double(frames)
                for i in 0..<frames {
                    guard !Task.isCancelled, isPlaying else { break }
                    slideThumb = place.clips[i].thumbnailData.flatMap { UIImage(data: $0) }
                    try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
                }
            }
            if !Task.isCancelled { isPlaying = false; slideThumb = nil }
        }
    }

    private func stopFlyover() {
        if isPlaying { isPlaying = false }
        slideThumb = nil
        flyTask?.cancel()
        flyTask = nil
    }

    // MARK: Helpers

    private func relativeLabel(forDay day: Int) -> String {
        let d = data.todayTag - day
        switch d {
        case 0: return String(localized: "today")
        case 1: return String(localized: "yesterday")
        default: break
        }
        if d > 1 && d < 7 { return String(localized: "\(d) days ago") }
        if d >= 7 && d < 14 { return String(localized: "1 week ago") }
        if d >= 14 && d < 56 { return String(localized: "\(Int((Double(d) / 7).rounded())) weeks ago") }
        if d >= 56 { return String(localized: "\(Int((Double(d) / 30).rounded())) months ago") }
        return String(localized: "today")
    }
}

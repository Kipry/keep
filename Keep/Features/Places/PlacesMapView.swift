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
    @State private var showUnlocatedInfo = false
    /// The place whose clip list is open. Set by tapping the preview card, or
    /// by tapping an already-selected pin a second time.
    @State private var detailPlace: Place?
    // One-shot: seed an explicit camera so the map is never .automatic while
    // pins exist (see seedCameraIfNeeded — prevents a re-fit feedback loop).
    @State private var didSeedCamera = false
    /// Camera flight in progress (see `fly(to:)`).
    @State private var flightTask: Task<Void, Never>?
    @State private var isFlying = false
    /// Altitude a flight lands at. Seeded with a street-level value and then
    /// tracked from whatever zoom the user settles on, so following the
    /// scrubber never quietly overrides the zoom they chose.
    @State private var followDistance: CLLocationDistance = 1400

    private let calendar = Calendar.current
    /// The route shows only travel within this many days before the focused
    /// day; older segments fade out and drop off the trailing edge.
    private let routeWindowDays = 10

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

    /// Cached clustering. `PlacesData.clusters` is O(places²) and the route is
    /// rebuilt from its result, so running it straight from the body meant the
    /// whole thing re-ran at touch-sampling frequency while scrubbing —
    /// `centerDay` is written continuously in the scrubber's drag. Only the
    /// rounded day and the zoom actually change the outcome, so it is
    /// recomputed on those instead. Same approach the timeline already takes
    /// with its per-day caches.
    @State private var cachedItems: [MapItem] = []

    private var mapItems: [MapItem] { cachedItems }

    private func rebuildClusters() {
        cachedItems = PlacesData.clusters(for: revealedPlaces,
                                          visibleRect: visibleRect,
                                          viewWidth: viewWidth)
    }

    // Route drawn between the CURRENTLY VISIBLE nodes (cluster centroids or
    // single places), so it always meets the pins at any zoom, and windowed to
    // the last `routeWindowDays` before the focused day with older segments
    // fading out — keeping long histories from cluttering the map.
    private struct RouteSegment: Identifiable {
        let id: Int
        let coords: [CLLocationCoordinate2D]
        let opacity: Double
    }

    private func routeSegments(from items: [MapItem]) -> [RouteSegment] {
        // Which node (cluster or single place) each place currently belongs to.
        var nodeID: [String: String] = [:]
        var nodeCoord: [String: CLLocationCoordinate2D] = [:]
        for item in items {
            switch item {
            case .place(let p):
                nodeID[p.key] = p.key
                nodeCoord[p.key] = p.coordinate
            case .cluster(let id, let coord, let members):
                for m in members { nodeID[m.key] = id; nodeCoord[m.key] = coord }
            }
        }
        // Chronological node path; collapse consecutive stays at the same node
        // (a back-and-forth trip still produces two segments).
        var nodes: [(coord: CLLocationCoordinate2D, day: Int)] = []
        var lastID: String?
        for place in revealedPlaces {
            guard let id = nodeID[place.key], let coord = nodeCoord[place.key] else { continue }
            if id == lastID { continue }
            lastID = id
            nodes.append((coord, place.firstDayTag))
        }
        guard nodes.count > 1 else { return [] }

        var result: [RouteSegment] = []
        for i in 1..<nodes.count {
            let opacity = routeOpacity(age: focusedDay - nodes[i].day)
            guard opacity > 0.03 else { continue }
            let coords = PlacesData.curvedSegment(MKMapPoint(nodes[i - 1].coord),
                                                  MKMapPoint(nodes[i].coord),
                                                  sign: i.isMultiple(of: 2) ? 1 : -1)
            result.append(RouteSegment(id: i, coords: coords, opacity: opacity))
        }
        return result
    }

    // Recent travel stays solid; the tail fades to nothing at the window edge.
    private func routeOpacity(age: Int) -> Double {
        if age <= 2 { return 1 }
        let t = Double(age - 2) / Double(routeWindowDays - 2)
        return max(0, 1 - t)
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
            // The flight goes too — otherwise the second half of an arc fires
            // after the user has taken the map and yanks it back.
            if byUser { follow = false; stopFlyover(); cancelFlight() }
        }
        .onChange(of: isActive) { _, active in
            if !active { stopFlyover(); cancelFlight() }
        }
        .onDisappear { stopFlyover(); cancelFlight() }
        .sheet(item: $detailPlace) { place in
            PlaceDetailSheet(
                place: place,
                relativeLabel: relativeLabel(forDay: place.firstDayTag),
                onOpenProject: { project in onOpenProject(project) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Map

    private var mapArea: some View {
        GeometryReader { geo in
            // Cluster once, then derive both the pins and the route from the same
            // assignment so the route always terminates on the visible dots.
            let clustered = mapItems
            let segments = routeVisible ? routeSegments(from: clustered) : []
            ZStack {
                Map(position: $camera) {
                    ForEach(segments) { seg in
                        MapPolyline(coordinates: seg.coords)
                            .stroke(Theme.amber.opacity(seg.opacity),
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 6]))
                    }
                    ForEach(clustered) { item in
                        Annotation("", coordinate: item.coordinate, anchor: .center) {
                            annotationView(for: item)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .onMapCameraChange(frequency: .onEnd) { ctx in
                    visibleRect = ctx.rect   // clustering input only
                    // Remember the altitude the user settles on. Only while
                    // they're driving: during a flight `follow` is on, so a
                    // flight can never move the goalposts for the next one.
                    if !follow {
                        followDistance = min(max(ctx.camera.distance, 250), 60_000)
                    }
                    // Don't re-cluster at the top of a flight arc. The camera
                    // is deliberately far out up there, so every pin would
                    // collapse into one blob and spring apart again on
                    // landing. Clustering depends on the zoom bucket and the
                    // revealed set, not on where the map is panned to, and a
                    // flight lands at the altitude it left from — so nothing
                    // can have changed by the end anyway.
                    guard !isFlying else { return }
                    rebuildClusters()
                }

                if places.places.isEmpty { emptyOverlay }
            }
            .overlay(alignment: .topLeading) {
                // Some clips have no location and can't appear on the map — make
                // that visible rather than silently dropping them.
                if !places.places.isEmpty && places.unlocatedCount > 0 {
                    unlocatedChip
                }
            }
            .overlay(alignment: .bottom) {
                if let place = activePlace { previewCard(for: place) }
            }
            .onAppear {
                viewWidth = geo.size.width
                seedCameraIfNeeded()
                rebuildClusters()
            }
            .onChange(of: geo.size.width) { _, w in viewWidth = w; rebuildClusters() }
            // The rounded day, not centerDay — the reveal set only changes when
            // the scrubber crosses a day boundary.
            .onChange(of: focusedDay) { _, _ in rebuildClusters() }
            .onChange(of: places.places.count) { _, _ in rebuildClusters() }
        }
        .alert("Moments without a location", isPresented: $showUnlocatedInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Some clips have no saved location, so they aren't shown on the map. They're still in your timeline.")
        }
    }

    private var unlocatedChip: some View {
        Button { showUnlocatedInfo = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "mappin.slash")
                Text("\(places.unlocatedCount)")
            }
            .font(.mono(10, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(12)
    }

    @ViewBuilder
    private func annotationView(for item: MapItem) -> some View {
        switch item {
        case .place(let place):
            let isActivePin = place.id == activePlace?.id
            Button {
                stopFlyover()
                // One tap does the obvious thing: show what was recorded here.
                // The day focus moves along, so dismissing the sheet leaves the
                // map and the scrubber on this place. Passing `place` straight
                // through avoids depending on which pin ends up "active" — with
                // several places on the same day that isn't necessarily this one.
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    centerDay = Double(place.firstDayTag)
                }
                detailPlace = place
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
                // Frame the members themselves rather than guessing a zoom step,
                // so a tap always actually breaks the cluster apart.
                expand(members, around: item.coordinate)
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
            stopFlyover()
            detailPlace = place
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

                // The place leads, the project is context — the card opens the
                // clips recorded here, so it should name the place.
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.displayName ?? String(localized: "Unknown place"))
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
        let clips = place.clipCount == 1
            ? String(localized: "1 CLIP")
            : String(localized: "\(place.clipCount) CLIPS")
        var parts = [clips, relativeLabel(forDay: place.firstDayTag)]
        if let project = place.project?.name { parts.append(project.uppercased()) }
        return parts.joined(separator: " · ")
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
            AmberChip(label: "TODAY") {
                stopFlyover()
                withAnimation(.easeOut(duration: 0.35)) { centerDay = Double(data.todayTag) }
            }

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
        // Honest, context-aware copy: distinguish "location is off" from
        // "location is on, there's just nothing located yet" (e.g. only older
        // clips, whose capture location can't be recovered).
        let enabled = LocationService.shared.isEnabled
        return VStack(spacing: 10) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.25))
            Text("No places yet")
                .font(.hand(22))
                .foregroundStyle(.white.opacity(0.7))
            Text(enabled
                 ? "As you record, new clips appear here — clips from before don't have a saved location."
                 : "Turn on location in Settings so new clips remember where they were captured.")
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

    /// One-time explicit framing so the camera is never `.automatic` while pins
    /// exist. `.automatic` re-fits whenever MapContent changes; our annotation
    /// set depends on `visibleRect` (clustering), and `visibleRect` is fed back
    /// by `onMapCameraChange`, so automatic + non-empty pins ping-pong forever.
    /// An explicit region pins the camera, so content changes never move it.
    private func seedCameraIfNeeded() {
        guard !didSeedCamera else { return }
        let seed = revealedPlaces.isEmpty ? places.places : revealedPlaces
        guard let region = Self.fittingRegion(for: seed) else { return }  // no pins → stay .automatic
        didSeedCamera = true
        camera = .region(region)
    }

    private static func fittingRegion(for places: [Place]) -> MKCoordinateRegion? {
        guard let first = places.first else { return nil }
        var minLat = first.coordinate.latitude,  maxLat = minLat
        var minLon = first.coordinate.longitude, maxLon = minLon
        for p in places.dropFirst() {
            minLat = min(minLat, p.coordinate.latitude);  maxLat = max(maxLat, p.coordinate.latitude)
            minLon = min(minLon, p.coordinate.longitude); maxLon = max(maxLon, p.coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        // 1.4x padding keeps pins off the edges; the floor handles the
        // single-place / zero-span case with a sensible neighbourhood zoom.
        let span = MKCoordinateSpan(latitudeDelta:  max((maxLat - minLat) * 1.4, 0.01),
                                    longitudeDelta: max((maxLon - minLon) * 1.4, 0.01))
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Where the map is looking right now. `visibleRect.origin` is the rect's
    /// *corner*, which put every distance estimate half a screen out.
    private var visibleCenter: CLLocationCoordinate2D {
        MKMapPoint(x: visibleRect.midX, y: visibleRect.midY).coordinate
    }

    /// Wall-clock length of a flight, exposed so the flyover can time its
    /// dwell against it.
    ///
    /// Square root of the distance rather than a linear ramp: a place ten
    /// times further away should not take ten times as long to reach. The
    /// arc's altitude is what conveys the distance; the duration only has to
    /// stay believable.
    private func flightDuration(to place: Place) -> Double {
        let meters = MKMapPoint(visibleCenter).distance(to: MKMapPoint(place.coordinate))
        return min(1.6, max(0.45, (meters / 1_000).squareRoot() * 0.16))
    }

    /// Flies the camera to `place` along an arc: climb away from where we are,
    /// cross at altitude, descend onto the target.
    ///
    /// Interpolating centre and distance straight from A to B — which is what
    /// a single `withAnimation` does — reads as a jump at map scale: the pins
    /// slide sideways and nothing conveys how far you actually travelled. The
    /// established answer is van Wijk & Nuij's "Smooth and Efficient Zooming
    /// and Panning" (2003), the algorithm behind Mapbox's `flyTo`, Google
    /// Earth's transitions and d3's `interpolateZoom`: it solves for the path
    /// through (x, y, log-zoom) space that a viewer perceives as shortest, and
    /// its defining property is that it pulls back automatically as the
    /// distance grows.
    ///
    /// We take the two-keyframe approximation of that curve rather than the
    /// closed form, because the full version has to be driven frame by frame —
    /// and every camera change we push settles `onMapCameraChange`, which is
    /// what feeds the clustering. Sixty re-clusters a second would cost far
    /// more than the remaining fidelity is worth. Two halves of one arc, with
    /// the apex placed so both ends fit in frame, gets the same read.
    private func fly(to place: Place) {
        cancelFlight()
        let target  = place.coordinate
        let landing = followDistance

        guard !reduceMotion else {
            camera = .camera(MapCamera(centerCoordinate: target, distance: landing))
            return
        }

        let origin = visibleCenter
        let meters = MKMapPoint(origin).distance(to: MKMapPoint(target))
        let total  = flightDuration(to: place)

        // Below roughly one screen of travel there is nothing to arc over —
        // climbing for a two-hundred-metre hop reads as a nervous twitch.
        guard meters > landing else {
            withAnimation(.easeInOut(duration: total)) {
                camera = .camera(MapCamera(centerCoordinate: target, distance: landing))
            }
            return
        }

        // Apex altitude. `MapCamera.distance` is roughly the span the camera
        // takes in at zero pitch, so the travelled distance is the natural
        // unit: a little more than that puts origin and target both in frame
        // at the top of the arc, which is the moment that makes the journey
        // legible.
        let apex = min(max(meters * 1.35, landing * 2), 12_000_000)
        let a = MKMapPoint(origin), b = MKMapPoint(target)
        let apexCenter = MKMapPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2).coordinate
        let half = total / 2

        isFlying = true
        flightTask = Task { @MainActor in
            // Climb away from the origin, accelerating…
            withAnimation(.easeIn(duration: half)) {
                camera = .camera(MapCamera(centerCoordinate: apexCenter, distance: apex))
            }
            try? await Task.sleep(nanoseconds: UInt64(half * 1_000_000_000))
            guard !Task.isCancelled else { return }

            // …then descend onto the target, decelerating. `easeIn` finishes
            // at full speed and `easeOut` starts at full speed, so the halves
            // join without a visible stall at the apex.
            withAnimation(.easeOut(duration: half)) {
                camera = .camera(MapCamera(centerCoordinate: target, distance: landing))
            }
            // Outlast the landing, so the camera-settled callback it triggers
            // is still suppressed and the single rebuild below is the one that
            // counts.
            try? await Task.sleep(nanoseconds: UInt64((half + 0.25) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            isFlying = false
            flightTask = nil
            rebuildClusters()
        }
    }

    /// Aborts a flight in the air. No rebuild here on purpose: `visibleRect`
    /// may currently hold the arc's apex, and re-clustering from that would
    /// briefly collapse every pin. Whatever moves the camera next — the user's
    /// gesture, the next flight — settles and rebuilds properly.
    private func cancelFlight() {
        flightTask?.cancel()
        flightTask = nil
        isFlying = false
    }

    /// Zooms so the cluster's own members fill the viewport, which is what
    /// actually separates them. A fixed "zoom one step in" could leave a tight
    /// cluster still clustered, so a tap appeared to do nothing.
    private func expand(_ members: [Place], around fallbackCenter: CLLocationCoordinate2D) {
        // Breaking a cluster open is the user framing the map themselves, so
        // hand the camera over: the settled altitude becomes the one the next
        // flight lands at, and scrubbing takes following back.
        cancelFlight()
        follow = false
        let position: MapCameraPosition
        if let region = Self.fittingRegion(for: members) {
            position = .region(region)
        } else {
            let metersPerMapPoint = MKMetersPerMapPointAtLatitude(visibleCenter.latitude)
            let currentMeters = visibleRect.size.height * metersPerMapPoint
            position = .camera(MapCamera(centerCoordinate: fallbackCenter,
                                         distance: max(600, currentMeters * 0.35)))
        }
        if reduceMotion { camera = position }
        else { withAnimation(.easeInOut(duration: 0.5)) { camera = position } }
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
                let travel = reduceMotion ? 0.1 : flightDuration(to: place)
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

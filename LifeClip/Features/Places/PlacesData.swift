import CoreLocation
import Foundation
import MapKit
import UIKit

// MARK: - Place

/// One spot on the map: all located clips whose coordinates group together.
/// `key` doubles as the SwiftUI identity — derived from the coordinate so the
/// same place keeps the same annotation view across rebuilds (a per-build UUID
/// would tear down and re-add every pin: flicker + thumbnail re-decode).
struct Place: Identifiable {
    let key: String
    let coordinate: CLLocationCoordinate2D
    /// Chronological (oldest first).
    let clips: [Clip]
    let heroClip: Clip
    let project: Project?
    /// Day-tag (days since TimelineData.startDate) of the first clip here.
    let firstDayTag: Int
    /// Pre-decoded hero thumbnail — never decode JPEG in an annotation body.
    let thumb: UIImage?

    var id: String { key }
    var clipCount: Int { clips.count }
    var displayName: String? { clips.compactMap(\.placeName).first }
}

// MARK: - Map items (clustered)

/// What the map actually renders at the current zoom: single places and
/// clusters of nearby ones. Identity is derived from member keys so identical
/// membership across recomputes diffs in place (no flicker).
enum MapItem: Identifiable {
    case place(Place)
    case cluster(id: String, coordinate: CLLocationCoordinate2D, places: [Place])

    var id: String {
        switch self {
        case .place(let p): return p.id
        case .cluster(let id, _, _): return id
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .place(let p): return p.coordinate
        case .cluster(_, let c, _): return c
        }
    }
}

// MARK: - PlacesData

/// Everything the Places map needs, aggregated once per timeline rebuild
/// (mirrors the cachedMonthSegs philosophy — never recomputed per frame).
struct PlacesData {
    /// Chronological by first visit.
    let places: [Place]
    /// Pre-sampled curved route points, one segment per consecutive place pair.
    /// The revealed polyline is `routeSegments.prefix(revealedCount).flatMap { $0 }`.
    let routeSegments: [[CLLocationCoordinate2D]]
    /// Sorted day-tags on which at least one place was first visited.
    let daysWithPlaces: [Int]
    /// Active clips that carry no coordinate — excluded from the map but
    /// surfaced as a subtle count so they aren't silently forgotten.
    let unlocatedCount: Int

    static let empty = PlacesData(places: [], routeSegments: [], daysWithPlaces: [], unlocatedCount: 0)

    // MARK: Build

    static func build(data: TimelineData, calendar: Calendar) -> PlacesData {
        // 1. Collect located, active clips across all projects (and count the rest).
        var located: [(clip: Clip, project: Project, coord: CLLocationCoordinate2D)] = []
        var unlocatedCount = 0
        for band in data.bands {
            for clip in band.project.activeClips {
                if let coord = clip.coordinate {
                    located.append((clip, band.project, coord))
                } else {
                    unlocatedCount += 1
                }
            }
        }
        // Keep the unlocated count even when nothing is on the map yet.
        guard !located.isEmpty else {
            return PlacesData(places: [], routeSegments: [], daysWithPlaces: [], unlocatedCount: unlocatedCount)
        }

        // 2. Group by 3-decimal grid (~110 m)…
        var groups: [String: [(clip: Clip, project: Project, coord: CLLocationCoordinate2D)]] = [:]
        for entry in located {
            let key = String(format: "%.3f_%.3f", entry.coord.latitude, entry.coord.longitude)
            groups[key, default: []].append(entry)
        }

        // …then merge groups whose centroids sit closer than ~150 m, so a spot
        // straddling a grid boundary doesn't split into two pins.
        var drafts: [(key: String, centroid: MKMapPoint, entries: [(clip: Clip, project: Project, coord: CLLocationCoordinate2D)])] = []
        for (key, entries) in groups.sorted(by: { $0.key < $1.key }) {
            let points = entries.map { MKMapPoint($0.coord) }
            let centroid = MKMapPoint(x: points.map(\.x).reduce(0, +) / Double(points.count),
                                      y: points.map(\.y).reduce(0, +) / Double(points.count))
            if let i = drafts.firstIndex(where: { $0.centroid.distance(to: centroid) < 150 }) {
                drafts[i].entries.append(contentsOf: entries)
            } else {
                drafts.append((key, centroid, entries))
            }
        }

        // 3. Materialize places (chronological hero = first clip at the spot).
        func dayTag(_ date: Date) -> Int {
            calendar.dateComponents([.day], from: data.startDate, to: calendar.startOfDay(for: date)).day ?? 0
        }
        var places: [Place] = drafts.map { draft in
            let clips = draft.entries.map(\.clip).sorted { $0.createdAt < $1.createdAt }
            let hero = clips[0]
            let thumb = hero.thumbnailData.flatMap { UIImage(data: $0)?.preparingThumbnail(of: CGSize(width: 168, height: 168)) }
            return Place(
                key: draft.key,
                coordinate: draft.centroid.coordinate,
                clips: clips,
                heroClip: hero,
                project: hero.project,
                firstDayTag: dayTag(hero.createdAt),
                thumb: thumb
            )
        }
        places.sort { ($0.firstDayTag, $0.heroClip.createdAt) < ($1.firstDayTag, $1.heroClip.createdAt) }

        // 4. Pre-sample the curved route between consecutive places.
        var segments: [[CLLocationCoordinate2D]] = []
        for i in 1..<max(places.count, 1) {
            segments.append(curvedSegment(
                MKMapPoint(places[i - 1].coordinate),
                MKMapPoint(places[i].coordinate),
                sign: i.isMultiple(of: 2) ? 1 : -1
            ))
        }

        let days = Array(Set(places.map(\.firstDayTag))).sorted()
        return PlacesData(places: places, routeSegments: segments, daysWithPlaces: days,
                          unlocatedCount: unlocatedCount)
    }

    /// Quadratic bezier between two map points, bulging perpendicular to the
    /// connecting line (alternating sides). Sampled in Mercator space so the
    /// curve doesn't distort with latitude.
    private static func curvedSegment(_ a: MKMapPoint, _ b: MKMapPoint, sign: Double) -> [CLLocationCoordinate2D] {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0 else { return [a.coordinate, b.coordinate] }
        let bulge = len * 0.18 * sign
        let ctrl = MKMapPoint(x: (a.x + b.x) / 2 - dy / len * bulge,
                              y: (a.y + b.y) / 2 + dx / len * bulge)
        return (0...16).map { i in
            let t = Double(i) / 16, u = 1 - t
            return MKMapPoint(x: u * u * a.x + 2 * u * t * ctrl.x + t * t * b.x,
                              y: u * u * a.y + 2 * u * t * ctrl.y + t * t * b.y).coordinate
        }
    }

    // MARK: Clustering

    /// Groups the given (already revealed) places into renderable map items for
    /// the current zoom. Works in absolute MKMapPoint space with a quantized
    /// zoom bucket, so panning never re-clusters — only zoom steps and reveal
    /// changes do. Greedy seed-distance keeps membership stable (centroids
    /// would drift and churn).
    static func clusters(for places: [Place], visibleRect: MKMapRect, viewWidth: CGFloat) -> [MapItem] {
        guard !places.isEmpty else { return [] }
        guard viewWidth > 0, visibleRect.size.width > 0 else {
            return places.map { .place($0) }
        }
        let mapPointsPerScreenPoint = visibleRect.size.width / Double(viewWidth)
        let zoomBucket = (log2(mapPointsPerScreenPoint)).rounded()
        let cell = 44.0 * pow(2.0, zoomBucket)   // ~44pt in map points

        var drafts: [(seed: MKMapPoint, members: [Place])] = []
        for place in places {
            let mp = MKMapPoint(place.coordinate)
            if let i = drafts.firstIndex(where: { $0.seed.distance(to: mp) < cell }) {
                drafts[i].members.append(place)
            } else {
                drafts.append((mp, [place]))
            }
        }

        return drafts.map { draft in
            if draft.members.count == 1 {
                return .place(draft.members[0])
            }
            let points = draft.members.map { MKMapPoint($0.coordinate) }
            let centroid = MKMapPoint(x: points.map(\.x).reduce(0, +) / Double(points.count),
                                      y: points.map(\.y).reduce(0, +) / Double(points.count))
            let id = draft.members.map(\.key).sorted().joined(separator: "|")
            return .cluster(id: id, coordinate: centroid.coordinate, places: draft.members)
        }
    }
}

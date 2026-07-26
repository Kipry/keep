import CoreLocation
import Foundation
import MapKit

// MARK: - Location granularity

/// How precisely capture locations are stored. Raw values are persisted in
/// UserDefaults under "locationGranularity" (default: .place).
enum LocationGranularity: String {
    case precise = "precise"
    case place   = "place"    // rounded to ~1.1 km — enough for "which town/quarter"
    case off     = "off"

    static var current: LocationGranularity {
        LocationGranularity(rawValue: UserDefaults.standard.string(forKey: "locationGranularity") ?? "") ?? .place
    }

    /// Applies this granularity to a raw coordinate. Returns nil for .off.
    func apply(to coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D? {
        switch self {
        case .off:     return nil
        case .precise: return coordinate
        case .place:
            // 2 decimal places ≈ 1.1 km — a real privacy reduction.
            return CLLocationCoordinate2D(
                latitude: (coordinate.latitude * 100).rounded() / 100,
                longitude: (coordinate.longitude * 100).rounded() / 100
            )
        }
    }
}

// MARK: - LocationService

/// One-shot location capture for clip saves plus cached reverse geocoding.
///
/// Lifecycle: `prime()` is called when the camera opens — the first call with
/// granularity ≠ off triggers the system permission dialog (the feature's
/// opt-in moment) and requests a single coarse fix so it's ready by the time
/// the clip is saved seconds later. `takeFix()` hands that fix to the save
/// path; if the fix hasn't arrived yet, `onNextFix` assigns it retroactively.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {

    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var lastFix: CLLocation?
    /// Pending retroactive assignment for a clip saved before the fix arrived.
    private var pendingFixHandler: ((CLLocationCoordinate2D) -> Void)?
    private var pendingFixDeadline: Date = .distantPast
    private var didRetryUnknown = false

    // Reverse-geocode results keyed by 3-decimal coordinates, mirrored to
    // UserDefaults so names survive restarts and each spot geocodes once.
    private var nameCache: [String: String]
    private var geocodeQueue: [Clip] = []
    private var isGeocoding = false

    private override init() {
        nameCache = (UserDefaults.standard.dictionary(forKey: "placeNameCache") as? [String: String]) ?? [:]
        super.init()
        manager.delegate = self
        // Coarse target — requestLocation() returns in a few seconds instead of
        // waiting for GPS convergence; coordinates get rounded anyway.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Whether new clips will actually capture a location — false only when the
    /// setting is off or the user denied/restricted access. `.notDetermined`
    /// counts as enabled (the prompt appears when the camera opens). Drives the
    /// wording of the empty Places state, nothing else.
    var isEnabled: Bool {
        guard LocationGranularity.current != .off else { return false }
        switch manager.authorizationStatus {
        case .denied, .restricted: return false
        default: return true
        }
    }

    // MARK: One-shot fix

    /// Called when the camera opens. First use (with location enabled in
    /// settings) shows the system permission prompt; afterwards it warms up a
    /// single fix so `takeFix()` can answer instantly at save time.
    func prime() {
        guard LocationGranularity.current != .off else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()   // fix requested on grant via delegate
        case .authorizedWhenInUse, .authorizedAlways:
            didRetryUnknown = false
            manager.requestLocation()
        default:
            break   // denied/restricted — feature silently inactive
        }
    }

    /// The most recent fix (if fresh), already reduced to the user's chosen
    /// granularity. Returns nil when off, denied, or no fix has arrived yet.
    func takeFix() -> CLLocationCoordinate2D? {
        guard let fix = lastFix, fix.timestamp > Date(timeIntervalSinceNow: -600) else { return nil }
        return LocationGranularity.current.apply(to: fix.coordinate)
    }

    /// Registers a one-shot handler for the next arriving fix (already
    /// granularity-reduced), valid for `seconds`. Covers the "opened camera and
    /// instantly recorded" case where the clip saves before the fix lands.
    func onNextFix(within seconds: TimeInterval, _ handler: @escaping (CLLocationCoordinate2D) -> Void) {
        guard LocationGranularity.current != .off else { return }
        pendingFixHandler = handler
        pendingFixDeadline = Date(timeIntervalSinceNow: seconds)
    }

    // MARK: Reverse geocoding

    /// Fills in `clip.placeName` from its coordinate — from the cache when this
    /// spot was seen before, otherwise via a queued MapKit reverse-geocode
    /// request (serialized, ~1 s apart, to stay well under rate limits).
    func geocodeIfNeeded(_ clip: Clip) {
        // This request is the app's only network egress, and the privacy policy
        // states it stops entirely when location is off. Without this guard a
        // clip that already carried a coordinate — captured before the user
        // switched off — would still send it to Apple.
        guard LocationGranularity.current != .off else { return }
        guard clip.placeName == nil, let coordinate = clip.coordinate else { return }
        if let cached = nameCache[Self.cacheKey(for: coordinate)] {
            clip.placeName = cached
            return
        }
        geocodeQueue.append(clip)
        drainGeocodeQueue()
    }

    private func drainGeocodeQueue() {
        guard !isGeocoding, !geocodeQueue.isEmpty else { return }
        isGeocoding = true
        let clip = geocodeQueue.removeFirst()
        Task { @MainActor in
            defer {
                isGeocoding = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    drainGeocodeQueue()
                }
            }
            guard clip.placeName == nil, let coordinate = clip.coordinate else { return }
            let key = Self.cacheKey(for: coordinate)
            if let cached = nameCache[key] { clip.placeName = cached; return }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let name = await Self.reverseGeocode(location), !name.isEmpty else { return }
            clip.placeName = name
            nameCache[key] = name
            UserDefaults.standard.set(nameCache, forKey: "placeNameCache")
        }
    }

    // MKReverseGeocodingRequest replaces CLGeocoder from iOS 26; below that,
    // CLGeocoder is still the only API (deployment target is iOS 18).
    private static func reverseGeocode(_ location: CLLocation) async -> String? {
        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            guard let item = try? await request.mapItems.first else { return nil }
            return item.name
        } else {
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
            // Neighbourhood/city-level naming matches the rounded coordinates.
            return placemark.subLocality ?? placemark.locality ?? placemark.name
        }
    }

    /// Two decimals ≈ 1.1 km — deliberately no finer than what "Nearby" itself
    /// stores. At three decimals this cache was a ~110 m record of everywhere
    /// the user had recorded, i.e. more precise than the coordinate they chose
    /// to save, sitting in plaintext preferences.
    private static func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.2f_%.2f", coordinate.latitude, coordinate.longitude)
    }

    /// Drops the whole cache. Called when the user turns location off and when
    /// the trash is swept — otherwise place names outlived both the setting and
    /// the clips they belonged to, with no way for the user to clear them.
    func clearNameCache() {
        nameCache = [:]
        UserDefaults.standard.removeObject(forKey: "placeNameCache")
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                guard LocationGranularity.current != .off else { return }
                self.didRetryUnknown = false
                manager.requestLocation()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.lastFix = location
            if let handler = self.pendingFixHandler, Date() < self.pendingFixDeadline,
               let reduced = LocationGranularity.current.apply(to: location.coordinate) {
                handler(reduced)
            }
            self.pendingFixHandler = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // "Location unknown" is transient — retry the one-shot once.
            if (error as? CLError)?.code == .locationUnknown, !self.didRetryUnknown {
                self.didRetryUnknown = true
                manager.requestLocation()
            }
        }
    }
}

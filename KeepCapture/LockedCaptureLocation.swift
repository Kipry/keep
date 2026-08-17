// Combine, for `ObservableObject` — the view holds this with `@StateObject`,
// which is what stops a fresh CLLocationManager being built on every body
// evaluation. The conformance comes from Combine, and this project enables
// MEMBER_IMPORT_VISIBILITY, so the defining module has to be named.
import Combine
import CoreLocation
import Foundation

// MARK: - Locked capture location

/// A single coarse fix, taken while the viewfinder is up.
///
/// Deliberately not `LocationService`: that one owns the reverse-geocoding
/// queue and touches `Clip`, so importing it here would drag SwiftData into a
/// process that has no store to read. Naming the place is the app's job on
/// import anyway — all this needs to do is answer "where are we, roughly",
/// once, before the clip is written.
///
/// Whether Core Location actually returns a fix on a locked device is not
/// something Apple documents either way: their list of what a capture
/// extension may not do covers the network, the App Group container and the
/// extension's own container, and says nothing about location. So this is
/// written to fail quietly. No fix means a clip with no coordinate, which is
/// precisely what happened before this existed.
@MainActor
final class LockedCaptureLocation: NSObject, ObservableObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var granularity: LocationGranularity = .off
    private var lastFix: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        // Coarse on purpose: `requestLocation()` answers in seconds instead of
        // waiting for GPS to converge, and the coordinate gets rounded anyway.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Starts warming up a fix, if the user's setting allows one at all.
    ///
    /// Never asks for permission. The app is where that conversation belongs —
    /// a system prompt on a locked Lock Screen would be a strange place to be
    /// asked, and someone who has not yet used the in-app camera has not opted
    /// into any of this. Without authorisation this simply does nothing.
    func prime(granularity: LocationGranularity) {
        self.granularity = granularity
        guard granularity != .off else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    /// The fix, reduced to the chosen granularity — or nil if none arrived,
    /// the one we have is stale, or location is off.
    func take() -> CLLocationCoordinate2D? {
        guard granularity != .off,
              let fix = lastFix,
              fix.timestamp > Date(timeIntervalSinceNow: -600) else { return nil }
        return granularity.apply(to: fix.coordinate)
    }

    /// Writes the sidecar next to a freshly recorded clip. Silent no-op when
    /// there is nothing worth writing.
    func writeSidecar(for movie: URL) {
        guard let coordinate = take() else { return }
        let metadata = LockedClipMetadata(latitude: coordinate.latitude,
                                          longitude: coordinate.longitude)
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: LockedClipMetadata.url(for: movie), options: .atomic)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in self.lastFix = latest }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // Nothing to recover: one attempt, and the clip files without a pin.
    }
}

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
    private var isUpdating = false

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
    ///
    /// Two changes from the obvious version, both about the same problem: a
    /// keep. clip is over in about a second and a half, and a cold GPS fix
    /// takes longer than that.
    ///
    /// `manager.location` first, because the system almost always already
    /// holds a recent fix from whatever last asked for one — that costs
    /// nothing and is frequently the whole answer. Then continuous updates
    /// rather than `requestLocation()`: the one-shot waits for the accuracy
    /// target before it reports anything, while updates hand over the first
    /// usable fix and improve on it, which is the right trade when the window
    /// is this short.
    func prime(granularity: LocationGranularity) {
        self.granularity = granularity
        guard granularity != .off else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: break
        default: return
        }
        if let cached = manager.location { lastFix = cached }
        guard !isUpdating else { return }
        isUpdating = true
        manager.startUpdatingLocation()
    }

    func stop() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
    }

    /// The fix, reduced to the chosen granularity — or nil if none arrived,
    /// the one we have is stale, or location is off.
    func take() -> CLLocationCoordinate2D? {
        guard granularity != .off,
              let fix = lastFix,
              fix.timestamp > Date(timeIntervalSinceNow: -600) else { return nil }
        return granularity.apply(to: fix.coordinate)
    }

    /// Writes the sidecar next to a freshly recorded clip, waiting a little for
    /// a first fix if none has landed yet.
    ///
    /// Waiting here rather than giving up is the point. The clip is already on
    /// disk and the confirmation screen is up, so a couple of seconds cost the
    /// user nothing — whereas recording faster than the GPS is exactly the
    /// normal case for this app, not an edge one. The wait is bounded because
    /// the alternative to a late pin is no pin, not a hung screen; dismissing
    /// the extension before it finishes simply means the clip files without
    /// one, which is the behaviour this replaced.
    func writeSidecar(for movie: URL) async {
        guard granularity != .off else { return }
        if take() == nil { await waitForFirstFix(upTo: 4) }
        guard let coordinate = take() else { return }
        let metadata = LockedClipMetadata(latitude: coordinate.latitude,
                                          longitude: coordinate.longitude)
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: LockedClipMetadata.url(for: movie), options: .atomic)
    }

    private func waitForFirstFix(upTo seconds: TimeInterval) async {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while lastFix == nil, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in self.lastFix = latest }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // Nothing to do: with continuous updates running, Core Location keeps
        // trying on its own, and a clip that files without a pin is the
        // documented worst case here.
    }
}

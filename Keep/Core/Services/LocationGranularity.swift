import CoreLocation
import Foundation

// MARK: - Location granularity

/// How precisely capture locations are stored. Raw values are persisted in
/// UserDefaults under "locationGranularity" (default: .place).
///
/// Lives apart from `LocationService` because the locked-capture extension
/// needs the rounding rule but must not pull in the service itself — that
/// carries the reverse-geocoding queue and a reference to `Clip`, i.e. all of
/// SwiftData, into a process that has no store to read. Two copies of the "2
/// decimal places" constant would be the worse trade: the number is a privacy
/// promise, and a promise kept in two places is one edit away from being
/// broken in one of them.
enum LocationGranularity: String {
    case precise = "precise"
    case place   = "place"    // rounded to ~1.1 km — enough for "which town/quarter"
    case off     = "off"

    /// The app's stored setting. Meaningless inside the capture extension —
    /// it cannot read the app's preferences — which is exactly why the setting
    /// is handed over through the intent's app context instead.
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

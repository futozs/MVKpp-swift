//
//  LocationProvider.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Combine
import CoreLocation
import Foundation

/// Why the app currently has (or lacks) a position. Mirrors the web app's
/// `useGeolocation` states so both clients tell the rider the same story.
enum GeoStatus {
    case idle, requesting, watching, denied, unavailable, error
}

struct GeoPosition: Codable, Equatable {
    let lat: Double
    let lon: Double
    let accuracyM: Double
    /// Unix seconds of the fix.
    let at: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// Location for the whole app: "nearest stop first" ordering, the *Hol vagyok?*
/// chip, the near-me radius filter, and the approach estimate.
///
/// Nothing starts until `start()` is called, and a rider who turns it off stays
/// off across launches — the opt-out is persisted, matching the web app's
/// `mvk_geo_enabled` key rather than re-prompting on every launch.
@MainActor
final class LocationProvider: NSObject, ObservableObject {
    @Published private(set) var status: GeoStatus = .idle
    @Published private(set) var position: GeoPosition?
    @Published private(set) var errorMessage: String?
    /// The shown position is a restored last-known fix, not a live one.
    @Published private(set) var isStale = false

    /// Kept for the watch app's existing call sites.
    var coordinate: CLLocationCoordinate2D? { position?.coordinate }
    var isActive: Bool { status == .watching }

    private static let enabledKey = "mvk_geo_enabled"
    nonisolated private static let lastFixKey = "mvk_geo_last_fix"
    /// The last fix lives in the App Group so the watch widget — which only
    /// gets a few seconds to find a position of its own — can fall back to
    /// where the app last saw the rider.
    nonisolated private static let sharedSuite = UserDefaults(suiteName: FavoritesStore.appGroupID) ?? .standard
    /// A fix older than this is not worth showing even as a placeholder.
    private static let lastFixMaxAge: TimeInterval = 30 * 60

    private let manager = CLLocationManager()
    private var isWatching = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
    }

    /// Call once at launch. Honours a previous opt-out and never prompts a
    /// rider who already denied the permission.
    func startIfPermitted() {
        guard UserDefaults.standard.string(forKey: Self.enabledKey) != "0" else { return }
        guard manager.authorizationStatus != .denied,
              manager.authorizationStatus != .restricted else { return }
        start()
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else {
            status = .unavailable
            errorMessage = "A helymeghatározás ki van kapcsolva a készüléken."
            return
        }
        guard !isWatching else { return }

        status = .requesting
        errorMessage = nil

        // Show the last known fix immediately so the map has somewhere to be
        // while the first real fix arrives.
        if let cached = Self.readLastFix() {
            position = cached
            isStale = true
        }

        isWatching = true
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        isWatching = false
        status = .idle
        position = nil
        isStale = false
        UserDefaults.standard.set("0", forKey: Self.enabledKey)
        Self.sharedSuite.removeObject(forKey: Self.lastFixKey)
    }

    // MARK: - Last known fix

    /// The last fix any app target stored, readable from an extension.
    nonisolated static func sharedLastFix(maxAge: TimeInterval) -> GeoPosition? {
        guard let data = sharedSuite.data(forKey: lastFixKey),
              let fix = try? JSONDecoder().decode(GeoPosition.self, from: data),
              Date().timeIntervalSince1970 - fix.at <= maxAge
        else { return nil }
        return fix
    }

    private static func readLastFix() -> GeoPosition? {
        sharedLastFix(maxAge: lastFixMaxAge)
    }

    private static func writeLastFix(_ fix: GeoPosition) {
        guard let data = try? JSONEncoder().encode(fix) else { return }
        sharedSuite.set(data, forKey: lastFixKey)
    }

    fileprivate func apply(_ location: CLLocation) {
        let fix = GeoPosition(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            accuracyM: location.horizontalAccuracy,
            at: location.timestamp.timeIntervalSince1970
        )
        position = fix
        isStale = false
        status = .watching
        errorMessage = nil
        UserDefaults.standard.set("1", forKey: Self.enabledKey)
        Self.writeLastFix(fix)
    }

    fileprivate func apply(_ error: Error) {
        // A transient "unknown location" while the first fix settles is not
        // worth surfacing — CoreLocation keeps trying on its own.
        if let clError = error as? CLError, clError.code == .locationUnknown { return }
        status = .error
        errorMessage = "A helyzet jelenleg nem elérhető."
    }

    fileprivate func applyDenied() {
        manager.stopUpdatingLocation()
        isWatching = false
        status = .denied
        position = nil
        isStale = false
        errorMessage = "A helymeghatározás le van tiltva ehhez az apphoz."
        UserDefaults.standard.set("0", forKey: Self.enabledKey)
        Self.sharedSuite.removeObject(forKey: Self.lastFixKey)
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.apply(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.apply(error) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                if self.isWatching { manager.startUpdatingLocation() }
            case .denied, .restricted:
                self.applyDenied()
            default:
                break
            }
        }
    }
}

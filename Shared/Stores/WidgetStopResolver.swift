//
//  WidgetStopResolver.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import CoreLocation
import Foundation

/// Decides which stop the watch widget shows.
///
/// With "nearest favourite" off it is the stop picked on the phone. With it
/// on, it is the watched stop closest to the rider — falling back to the
/// picked stop, then to the top of the watchlist, whenever there is no
/// position or no coordinates to compare against.
enum WidgetStopResolver {
    /// How old a fix the watch app left behind may be and still decide the
    /// stop. Past this, the phone's explicit pick is a better guess.
    private static let sharedFixMaxAge: TimeInterval = 2 * 60 * 60
    private static let locationTimeout: Duration = .seconds(5)

    static func resolveStopId() async -> String? {
        let picked = FavoritesStore.storedWidgetStopId
        guard FavoritesStore.storedWidgetNearestEnabled else { return picked }

        let watched = FavoritesStore.storedStopIds
        let fallback = picked ?? watched.first
        guard watched.count > 1 else { return fallback }
        guard let position = await currentPosition() else { return fallback }

        let candidates = await watchedStops(watched)
        let nearest = Geo.nearest(candidates, lat: position.latitude, lon: position.longitude) {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        return nearest?.item.id ?? fallback
    }

    // MARK: - Position

    private static func currentPosition() async -> CLLocationCoordinate2D? {
        if let live = await WidgetLocationFetcher().fetch(timeout: locationTimeout) {
            return live.coordinate
        }
        return LocationProvider.sharedLastFix(maxAge: sharedFixMaxAge)?.coordinate
    }

    // MARK: - Stop coordinates

    /// The watched stops that have coordinates, from the App Group mirror —
    /// topped up from the gateway when a watched stop is missing from it.
    private static func watchedStops(_ watched: [String]) async -> [CachedStop] {
        let cached = matching(SharedStopCache.load(), watched)
        guard cached.count < watched.count else { return cached }

        guard let fetched = try? await APIClient.shared.stops(), !fetched.isEmpty else {
            return cached
        }
        SharedStopCache.save(fetched)
        return matching(fetched.map(CachedStop.init), watched)
    }

    private static func matching(_ stops: [CachedStop], _ watched: [String]) -> [CachedStop] {
        let watchedSet = Set(watched)
        return stops.filter { watchedSet.contains($0.id) }
    }
}

/// One-shot location for a widget timeline: whatever CoreLocation can give
/// within the timeout, or its cached fix, or nothing.
@MainActor
private final class WidgetLocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    func fetch(timeout: Duration) async -> CLLocation? {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            return nil
        }

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.finish(nil)
        }
        defer { timeoutTask.cancel() }

        let location = await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
        return location ?? manager.location
    }

    private func finish(_ location: CLLocation?) {
        guard let continuation else { return }
        self.continuation = nil
        manager.stopUpdatingLocation()
        continuation.resume(returning: location)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

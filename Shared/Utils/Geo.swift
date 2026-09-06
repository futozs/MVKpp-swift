//
//  Geo.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import CoreLocation
import Foundation

enum Geo {

    /// Great-circle distance in kilometres (haversine).
    static func distanceKm(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
        let earthRadiusKm = 6371.0
        let dLat = (bLat - aLat) * .pi / 180
        let dLon = (bLon - aLon) * .pi / 180
        let s = pow(sin(dLat / 2), 2)
            + cos(aLat * .pi / 180) * cos(bLat * .pi / 180) * pow(sin(dLon / 2), 2)
        return 2 * earthRadiusKm * asin(sqrt(s))
    }

    static func distanceKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        distanceKm(a.latitude, a.longitude, b.latitude, b.longitude)
    }

    /// Distance in the rider's words: metres up close, one decimal beyond a
    /// kilometre. Rounded to 10 m in the middle band so the readout does not
    /// twitch on every GPS update.
    static func formatDistance(_ km: Double) -> String {
        let m = km * 1000
        if m < 100 { return "\(Int(m.rounded())) m" }
        if m < 950 { return "\(Int((m / 10).rounded()) * 10) m" }
        return String(format: "%.1f km", km).replacingOccurrences(of: ".", with: ",")
    }

    struct PathProjection {
        /// Distance travelled along the path to reach the projected point.
        let alongKm: Double
        /// Perpendicular distance from the point to the path.
        let distKm: Double
    }

    /// Projects a point onto a polyline, in an equirectangular approximation
    /// anchored at the path's first vertex. Over a city-sized route the error
    /// is far below GPS noise, and it avoids a haversine per segment.
    ///
    /// This is what lets the app say "the bus is 1.2 km behind you *on its
    /// route*" instead of a meaningless straight-line distance.
    static func projectOntoPath(_ path: [CLLocationCoordinate2D], lat: Double, lon: Double) -> PathProjection? {
        guard path.count >= 2 else { return nil }

        let kx = 111.32 * cos(path[0].latitude * .pi / 180)
        let ky = 111.32
        let px = lon * kx
        let py = lat * ky

        var cumKm = 0.0
        var bestDistKm = Double.infinity
        var bestAlongKm = 0.0

        for i in 0..<(path.count - 1) {
            let ax = path[i].longitude * kx
            let ay = path[i].latitude * ky
            let bx = path[i + 1].longitude * kx
            let by = path[i + 1].latitude * ky
            let dx = bx - ax
            let dy = by - ay
            let segLen2 = dx * dx + dy * dy
            let t = segLen2 > 0
                ? max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / segLen2))
                : 0
            let projX = ax + t * dx
            let projY = ay + t * dy
            let dist = hypot(px - projX, py - projY)

            if dist < bestDistKm {
                bestDistKm = dist
                bestAlongKm = cumKm + hypot(projX - ax, projY - ay)
            }
            cumKm += hypot(dx, dy)
        }

        return PathProjection(alongKm: bestAlongKm, distKm: bestDistKm)
    }

    struct NearestHit<T> {
        let item: T
        let km: Double
    }

    /// The closest entry, skipping anything without coordinates.
    static func nearest<T>(
        _ list: [T],
        lat: Double,
        lon: Double,
        coordinate: (T) -> CLLocationCoordinate2D?
    ) -> NearestHit<T>? {
        var best: NearestHit<T>?
        for item in list {
            guard let c = coordinate(item) else { continue }
            let km = distanceKm(lat, lon, c.latitude, c.longitude)
            if best == nil || km < best!.km {
                best = NearestHit(item: item, km: km)
            }
        }
        return best
    }

    static func nearest(_ stops: [Stop], lat: Double, lon: Double) -> NearestHit<Stop>? {
        nearest(stops, lat: lat, lon: lon) { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }
}

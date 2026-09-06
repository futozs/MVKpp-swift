//
//  LiveVehicle.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import CoreLocation
import Foundation

/// One vehicle from `/live/positions`. `lat`/`lon` are nullable because the
/// feed occasionally reports a trip with no fix yet — those are filtered out
/// before anything is drawn.
struct LiveVehicle: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
    let routeId: String
    let routeShort: String
    let routeColor: String
    let routeText: String
    let headsign: String
    let lat: Double?
    let lon: Double?
    let bearing: Double?
    /// Metres per second, as GTFS-RT reports it.
    let speed: Double?
    let tripId: String
    let timestamp: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// The rider-facing speed. GTFS-RT gives m/s; every readout shows km/h.
    var speedKmh: Int? {
        guard let speed else { return nil }
        return Int((speed * 3.6).rounded())
    }

    /// Trams report `type == "900"` on their route, but some vehicles only
    /// carry the hint in `label` — the web app checks both.
    func isTram(routes: [String: Route]) -> Bool {
        routes[routeId]?.type == "900" || label == "TRAM"
    }
}

struct VehiclePositionsHeader: Decodable, Hashable {
    let version: String?
    let timestamp: Double
}

struct VehiclePositionsResponse: Decodable {
    let header: VehiclePositionsHeader
    let vehicles: [LiveVehicle]
}

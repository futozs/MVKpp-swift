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
    /// v3, WebSocket only: where the vehicle is along its shape, for the
    /// map's smooth estimate between pushes.
    var motion: LiveMotion?
    var mode: TransitMode?
    var routeKey: String?
    var plate: String?
    var trainNo: String?
    var trainName: String?
    /// Official delay at the next stop (regional feeds and the fallback source).
    var delaySec: Int?
    /// Position estimated from the timetable, not GPS.
    var estimated: Bool?
    var source: String?
    /// Our own matcher's measured delay right now (WebSocket).
    var liveDelaySec: Int?

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

/// A vehicle's place on its shape (`s`), pushed over the WebSocket: `a` metres
/// along, `t` the fix time (unix s), `e` the next stop (m), `v` expected speed
/// (m/s), and `k` the expected path as `[along m, seconds since fix]` pairs.
struct LiveMotion: Codable, Hashable {
    let s: String
    let a: Double
    let t: Double
    let e: Double
    let v: Double
    let k: [[Double]]?
}

extension LiveVehicle {
    private enum CodingKeys: String, CodingKey {
        case id, label, routeId, routeShort, routeColor, routeText, headsign, lat, lon, bearing, speed, tripId, timestamp
        case motion, mode, routeKey, plate, trainNo, trainName, delaySec, estimated, source, liveDelaySec
    }

    /// Only the id is required: any other field the feed sends empty, as a
    /// number, or with a value this build does not know reads as missing, so
    /// the vehicle still shows (the web renders it either way).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientString(.id), !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Vehicle without an id")
        }
        self.init(
            id: id,
            label: c.lenientString(.label) ?? "",
            routeId: c.lenientString(.routeId) ?? "",
            routeShort: c.lenientString(.routeShort) ?? "",
            routeColor: c.lenientString(.routeColor) ?? "",
            routeText: c.lenientString(.routeText) ?? "",
            headsign: c.lenientString(.headsign) ?? "",
            lat: c.lenientDouble(.lat),
            lon: c.lenientDouble(.lon),
            bearing: c.lenientDouble(.bearing),
            speed: c.lenientDouble(.speed),
            tripId: c.lenientString(.tripId) ?? "",
            timestamp: c.lenientDouble(.timestamp),
            motion: c.lenient(LiveMotion.self, .motion),
            mode: c.lenient(TransitMode.self, .mode),
            routeKey: c.lenientString(.routeKey),
            plate: c.lenientString(.plate),
            trainNo: c.lenientString(.trainNo),
            trainName: c.lenientString(.trainName),
            delaySec: c.lenientInt(.delaySec),
            estimated: c.lenient(Bool.self, .estimated),
            source: c.lenientString(.source),
            liveDelaySec: c.lenientInt(.liveDelaySec)
        )
    }
}

struct VehiclePositionsHeader: Decodable, Hashable {
    let version: String?
    let timestamp: Double
}

struct VehiclePositionsResponse: Decodable {
    let header: VehiclePositionsHeader
    let vehicles: [LiveVehicle]

    private enum CodingKeys: String, CodingKey { case header, vehicles }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        header = try c.decode(VehiclePositionsHeader.self, forKey: .header)
        vehicles = Array(lenient: try c.decode([Lenient<LiveVehicle>].self, forKey: .vehicles))
    }
}

//
//  RoutePlan.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import CoreLocation
import Foundation

struct RoutePlanPoint: Codable, Hashable {
    let lat: Double
    let lon: Double

    init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        lat = coordinate.latitude
        lon = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// One continuous stretch of a planned journey — a walk, or a ride on a single
/// route. `polyline` is an encoded polyline string when the planner supplies
/// geometry for the leg.
struct RoutePlanLeg: Decodable, Hashable, Identifiable {
    let mode: String
    let routeShortName: String?
    let routeLongName: String?
    let routeColor: String?
    let polyline: String?
    let fromStopId: String?
    let fromName: String
    let from: RoutePlanPoint
    let toStopId: String?
    let toName: String
    let to: RoutePlanPoint
    let start: String
    let end: String
    let durationSec: Int
    let distanceMeter: Int
    let intermediateStopNames: [String]

    var id: String { "\(mode)-\(fromName)-\(toName)-\(start)" }

    var isWalk: Bool { mode.uppercased().contains("WALK") }
}

struct RoutePlanTrip: Decodable, Hashable, Identifiable {
    let logDetailsId: Int
    let travelProfile: String
    let start: String
    let end: String
    let durationSec: Int
    let distanceMeter: Int
    let legs: [RoutePlanLeg]

    var id: Int { logDetailsId }
}

struct RoutePlanResponse: Decodable {
    let logHeaderId: Int
    let trips: [RoutePlanTrip]
}

struct RoutePlanRequest: Encodable {
    let points: [RoutePlanPoint]
    let departureTime: String
}

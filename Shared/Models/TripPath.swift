//
//  TripPath.swift
//  MVK++ (shared by the Watch and Phone targets)
//

import Foundation

/// The full route shape for a trip, used to draw the polyline on the map.
struct TripPathResponse: Decodable {
    let trip: String
    let route: String
    let color: String
    let text: String
    let headsign: String
    /// [lat, lon] points along the route, in order.
    let shape: [[Double]]
    let vehicle: ArrivalVehicle?
    let nextStop: TripProgressStop?
    let scheduleDeviationSec: Int?
}

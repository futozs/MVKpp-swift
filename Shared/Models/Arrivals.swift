//
//  Arrivals.swift
//  MVK++ Watch App
//

import Foundation

/// The vehicle the gateway matched to an arrival, when GPS + trip_update
/// correlation succeeded. Absent means "schedule-only, no live match".
struct ArrivalVehicle: Decodable, Hashable {
    let id: String
    let lat: Double
    let lon: Double
    let bearing: Double?
    let speed: Double?
    let routeId: String
    let tripId: String
}

struct ArrivalItem: Decodable, Hashable, Identifiable {
    let route: String
    let color: String
    let text: String
    let headsign: String
    let time: String
    let etaMin: Int
    /// Seconds; positive = late, negative = early, nil = no live data (not "on time").
    let delaySec: Int?
    let live: Bool
    let tripId: String
    let vehicle: ArrivalVehicle?
    let currentStopName: String?
    let distanceToStopKm: Double?
    let progressDesc: String?

    var id: String { "\(tripId)-\(time)" }
}

struct StopSummary: Decodable, Hashable {
    let id: String
    let code: String?
    let name: String?
    let lat: Double?
    let lon: Double?
}

struct StopArrivalsResponse: Decodable {
    let stop: StopSummary
    let now: Double
    let rtError: String?
    let arrivals: [ArrivalItem]
}

struct MultiArrivalsResponse: Decodable {
    let results: [StopArrivalsResponse]
}

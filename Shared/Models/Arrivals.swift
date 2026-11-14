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
    var mode: TransitMode?
    var plate: String?
    var trainNo: String?
    var trainName: String?
    /// MÁV's official delay; for trains this is what the timetable uses.
    var delaySec: Int?
}

/// The bus that should run this trip is still on its previous one.
struct ArrivalStartRisk: Decodable, Hashable {
    let vehicleId: String
    let expectedDelayS: Double
    /// `late` or `likely-missed`.
    let level: String
    let prevRoute: String?
    let prevEndUnix: Double
    let predicted: Bool
}

/// Congestion between the bus and the stop.
struct ArrivalTrafficAhead: Decodable, Hashable {
    let excessS: Double
    let level: Double
    let fromName: String
    let toName: String
}

struct PredictedVehicle: Decodable, Hashable {
    let id: String
    let confidence: Double
    let method: String?
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
    /// v3: our own matcher's measured delay now.
    var measuredDelaySec: Int?
    var predictedVehicle: PredictedVehicle?
    var cancelled: Bool?
    /// v3: expected delay at this stop and its 85th percentile.
    var forecastDelaySec: Int?
    var forecastUpperSec: Int?
    var schedUnix: Double?
    var startRisk: ArrivalStartRisk?
    var trafficAhead: ArrivalTrafficAhead?
    var mode: TransitMode?
    var routeKey: String?
    var `operator`: String?
    var trainNo: String?
    var trainName: String?
    var platform: String?
    var platformChanged: Bool?
    var platformPredicted: Bool?
    var stopId: String?
    var notices: [String]?

    var id: String { "\(tripId)-\(time)" }

    /// Built from the gateway's JSON in normal use. The explicit initializer
    /// exists so the offline pack can produce the same rows from the stored
    /// timetable, and every screen keeps rendering one arrival type.
    init(
        route: String,
        color: String,
        text: String,
        headsign: String,
        time: String,
        etaMin: Int,
        delaySec: Int? = nil,
        live: Bool = false,
        tripId: String,
        vehicle: ArrivalVehicle? = nil,
        currentStopName: String? = nil,
        distanceToStopKm: Double? = nil,
        progressDesc: String? = nil
    ) {
        self.route = route
        self.color = color
        self.text = text
        self.headsign = headsign
        self.time = time
        self.etaMin = etaMin
        self.delaySec = delaySec
        self.live = live
        self.tripId = tripId
        self.vehicle = vehicle
        self.currentStopName = currentStopName
        self.distanceToStopKm = distanceToStopKm
        self.progressDesc = progressDesc
    }
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
    /// v3: shared stop — the board lists the departures of all of these.
    var merged: [String]?
    let now: Double
    let rtError: String?
    let arrivals: [ArrivalItem]
}

struct MultiArrivalsResponse: Decodable {
    let results: [StopArrivalsResponse]
}

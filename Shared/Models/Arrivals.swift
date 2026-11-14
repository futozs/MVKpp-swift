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
    /// v3: MVK pulled this run; it is listed so the gap is visible.
    var cancelled: Bool? = nil
    /// v3: "tram", "bus", "coach" or "rail".
    var mode: String? = nil
    /// v3: the vehicle expected to run this trip before it reports live.
    var predictedVehicle: PredictedVehicle? = nil

    var id: String { "\(tripId)-\(time)" }

    var isCancelled: Bool { cancelled == true }

    struct PredictedVehicle: Decodable, Hashable {
        let id: String
        let confidence: Double?
    }

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
    let now: Double
    let rtError: String?
    let arrivals: [ArrivalItem]
}

struct MultiArrivalsResponse: Decodable {
    let results: [StopArrivalsResponse]
}

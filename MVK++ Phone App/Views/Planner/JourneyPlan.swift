//
//  JourneyPlan.swift
//  MVK++ Phone App
//

import Foundation

/// Our own planner (`/engine/plan`): one source for the timetable, measured
/// lateness and live data. ISO timestamps arrive in UTC; the `sched*`, `depTs`
/// and `arrTs` fields are unix seconds.
enum JourneyMode: String, Decodable {
    case past, now, future
}

enum TransferRisk: String, Decodable {
    case safe, tight, risky

    var order: Int {
        switch self {
        case .safe: return 0
        case .tight: return 1
        case .risky: return 2
        }
    }
}

struct JourneyPlace: Decodable, Hashable {
    let lat: Double
    let lon: Double
    let name: String
}

struct JourneyPoint: Decodable, Hashable {
    let lat: Double
    let lon: Double
}

struct JourneyPrediction: Decodable, Hashable {
    /// `live`, `history` or `none`.
    let source: String
    let depDelayS: Double?
    let arrDelayS: Double?
    let arrDelayP85S: Double?
    let samples: Double
    let vehicleId: String?
}

struct JourneyActual: Decodable, Hashable {
    let tracked: Bool
    let vehicleId: String?
    let depTs: Double?
    let arrTs: Double?
    let depDelayS: Double?
    let arrDelayS: Double?
    /// The alighting time was not measured but read off the vehicle's track.
    let estimated: Bool
}

/// A walk (`mode == "WALK"`) or a ride. The transit-only fields are absent on walks.
struct JourneyLeg: Decodable, Hashable {
    let mode: String
    let fromName: String
    let toName: String
    let from: JourneyPoint
    let to: JourneyPoint
    let start: String
    let end: String
    let durationSec: Double
    let distanceMeter: Double

    let routeShortName: String?
    let routeKey: String?
    let tripShortName: String?
    let trainNo: String?
    let trainName: String?
    let fromPlatform: String?
    let routeLongName: String?
    let routeColor: String?
    let routeTextColor: String?
    let tripId: String?
    let headsign: String?
    let fromStopId: String?
    let toStopId: String?
    let intermediateStopNames: [String]?
    let schedDep: Double?
    let schedArr: Double?
    let prediction: JourneyPrediction?
    let actual: JourneyActual?

    var isTransit: Bool { mode != "WALK" }
    var isRail: Bool { mode == "RAIL" }
    var stopsBetween: [String] { intermediateStopNames ?? [] }
}

struct JourneyFallbackDeparture: Decodable, Hashable {
    let tripId: String
    let time: String
    let departUnix: Double
}

struct JourneyTransferCheck: Decodable, Hashable {
    let at: String
    let marginSec: Double
    let risk: TransferRisk
    /// 0…1 — the odds of making the connection.
    let chance: Double?
    /// If missed, the next run of the same line today.
    let fallback: JourneyFallbackDeparture?
    let fromTripId: String?
    let toTripId: String?
    let alightStopId: String?
    let boardStopId: String?
    let walkS: Double?
    let fromRoute: String?
    let toRoute: String?
}

struct JourneyActualOutcome: Decodable, Hashable {
    let tracked: Bool
    let departedDelayS: Double?
    let arrivedDelayS: Double?
    let vehicles: [String?]
}

struct JourneyTrip: Decodable, Hashable {
    let start: String
    let end: String
    let durationSec: Double
    let distanceMeter: Double
    let transfers: Int
    let transferChecks: [JourneyTransferCheck]
    let legs: [JourneyLeg]
    let actualOutcome: JourneyActualOutcome?
}

struct JourneySchedule: Decodable, Hashable {
    let feedVersion: String
    /// `feed` or `legacy`.
    let source: String
    /// The template day used when MVK published no timetable for this day.
    let fallback: String?
}

struct JourneyPlanResponse: Decodable {
    let date: String
    let at: Double
    let mode: JourneyMode
    let arriveBy: Bool
    let schedule: JourneySchedule
    let from: JourneyPlace
    let to: JourneyPlace
    let trips: [JourneyTrip]
}

struct JourneyPlanQuery: Equatable {
    /// `stop:<stopId>` or `<lat>,<lon>`.
    var from: String
    var to: String
    /// Unix seconds.
    var at: Int
    var arriveBy: Bool
    var limit: Int = 4
    var modes: String
}

/// The planner's own message for the rider, already in Hungarian.
struct JourneyPlanError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// One stop from `/gtfs/stops.json?modes=`, with the v3 extras the planner
/// filters on: the feed, the parent station, and the MVK twin of a Volán stop.
struct PlannerPlace: Decodable, Hashable, Identifiable {
    let id: String
    let code: String
    let name: String
    let lat: Double
    let lon: Double
    let feed: String?
    let parent: String?
    let station: Bool
    let twinOf: String?

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        id = try container.decode(String.self)
        code = try container.decode(String.self)
        name = try container.decode(String.self)
        lat = try container.decode(Double.self)
        lon = try container.decode(Double.self)
        feed = Self.nonEmpty(container.isAtEnd ? nil : try container.decodeIfPresent(String.self))
        parent = Self.nonEmpty(container.isAtEnd ? nil : try container.decodeIfPresent(String.self))
        let stationFlag = container.isAtEnd ? nil : try container.decodeIfPresent(Double.self)
        station = (stationFlag ?? 0) != 0
        twinOf = Self.nonEmpty(container.isAtEnd ? nil : try container.decodeIfPresent(String.self))
    }

    init(stop: Stop) {
        id = stop.id
        code = stop.code
        name = stop.name
        lat = stop.lat
        lon = stop.lon
        feed = stop.feed
        parent = stop.parent
        station = stop.station
        twinOf = stop.twinOf
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    var resolvedFeed: TransitFeed {
        if let feed, let parsed = TransitFeed(rawValue: feed), parsed != .mvk { return parsed }
        return TransitFeed.of(id: id)
    }
}

extension APIClient {
    /// Plans with measured reality for a past day, and the expected lateness
    /// (live or from earlier measurements) for today and later. On failure
    /// the backend's own Hungarian `error` is surfaced.
    func planJourney(_ q: JourneyPlanQuery) async throws -> JourneyPlanResponse {
        var items = [
            URLQueryItem(name: "from", value: q.from),
            URLQueryItem(name: "to", value: q.to),
            URLQueryItem(name: "at", value: String(q.at)),
            URLQueryItem(name: "limit", value: String(q.limit)),
            URLQueryItem(name: "modes", value: q.modes),
        ]
        if q.arriveBy { items.append(URLQueryItem(name: "arriveBy", value: "1")) }
        let (data, response) = try await session.data(from: try url(path: "/engine/plan", queryItems: items))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let message = body?["error"] as? String, !message.isEmpty {
                throw JourneyPlanError(message: message)
            }
            throw JourneyPlanError(message: "Az útvonaltervező most nem érhető el (HTTP \(http.statusCode)).")
        }
        return try decode(data)
    }

    /// The stops of the given modes, with feed, parent station and twin.
    func plannerPlaces(modes: String) async throws -> [PlannerPlace] {
        try await request(path: "/gtfs/stops.json", queryItems: [URLQueryItem(name: "modes", value: modes)])
    }
}

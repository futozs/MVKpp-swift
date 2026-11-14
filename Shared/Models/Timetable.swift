//
//  Timetable.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// One direction of a route on a given day. `dir` is the GTFS direction id as
/// a string, because the feed is not consistent about 0/1 vs. named values.
struct TimetableDirection: Decodable, Hashable, Identifiable {
    let dir: String
    let headsign: String
    let tripsToday: Int
    let tripsTotal: Int
    let firstDeparture: String?

    var id: String { dir }
}

/// A route as `/gtfs/timetable/routes` returns it — keyed, with its directions
/// attached, unlike the tuple-shaped `/gtfs/routes.json`.
struct TimetableRoute: Decodable, Hashable, Identifiable {
    let id: String
    let short: String
    let long: String
    let type: String
    let color: String
    let text: String
    let directions: [TimetableDirection]
    /// v3 (`?modes=`): mode, statistics key, operator.
    var mode: TransitMode?
    var key: String?
    var `operator`: String?

    /// The route's mode; the old list leaves it to the GTFS type.
    var transitMode: TransitMode {
        if let mode { return mode }
        switch TransitFeed.of(id: id) {
        case .coach: return .coach
        case .rail: return .rail
        case .mvk: return type == "900" || type == "0" ? .tram : .bus
        }
    }
}

struct TimetableRoutesResponse: Decodable {
    let date: String
    let routes: [TimetableRoute]
}

/// A stop as it appears in a timetable column header. Unlike the GTFS catalog
/// `Stop`, coordinates may be missing here.
struct TimetableStop: Decodable, Hashable, Identifiable {
    let id: String
    let code: String
    let name: String
    let lat: Double?
    let lon: Double?
}

/// One run of the route. `times` is aligned with `TimetableResponse.stops`;
/// a `nil` entry means this run skips that stop.
struct TimetableTrip: Decodable, Hashable, Identifiable {
    let tripId: String
    let headsign: String
    let departure: String
    let departureSec: Int
    let arrival: String
    let arrivalSec: Int
    let originName: String
    let destinationName: String
    let stopCount: Int
    /// The run does not serve every stop of the direction.
    let deviates: Bool
    /// The run's headsign differs from the direction's own.
    let headsignDiffers: Bool
    /// Route-variant letter for a run off the base path; explained in
    /// `TimetableResponse.variants`.
    var variant: String?
    let times: [String?]

    var id: String { tripId }
}

/// "A = Avas városközpont érintésével" — how a lettered run differs.
struct TimetableVariant: Decodable, Hashable, Identifiable {
    let code: String
    let label: String
    let trips: Int

    var id: String { code }
}

struct TimetableResponse: Decodable {
    let route: Route
    let dir: String
    let date: String
    let headsign: String
    let stops: [TimetableStop]
    let trips: [TimetableTrip]
    let note: String?
    var variants: [TimetableVariant]?
}
